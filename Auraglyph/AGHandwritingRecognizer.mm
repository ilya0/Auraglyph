//
//  AGHandwritingRecognizer.m
//  Auragraph
//
//  Created by Spencer Salazar on 8/9/13.
//  Copyright (c) 2013 Spencer Salazar. All rights reserved.
//

#import "AGHandwritingRecognizer.h"

#include "LTKLipiEngineInterface.h"
#include "LTKMacros.h"
#include "LTKInc.h"
#include "LTKTypes.h"
#include "LTKTrace.h"
#include "LTKLoggerUtil.h"
#include "LTKErrors.h"
#include "LTKOSUtilFactory.h"
#include "LTKOSUtil.h"


extern "C" LTKLipiEngineInterface* createLTKLipiEngine();


static AGHandwritingRecognizerFigure g_figureForNumeralShape[] =
{
    AG_FIGURE_0,
    AG_FIGURE_1,
    AG_FIGURE_2,
    AG_FIGURE_3,
    AG_FIGURE_4,
    AG_FIGURE_5,
    AG_FIGURE_6,
    AG_FIGURE_7,
    AG_FIGURE_8,
    AG_FIGURE_9,
    AG_FIGURE_NONE,
};

static AGHandwritingRecognizerFigure g_figureForShape[] =
{
    AG_FIGURE_CIRCLE,
    AG_FIGURE_SQUARE,
    AG_FIGURE_TRIANGLE_UP,
    AG_FIGURE_TRIANGLE_DOWN,
    AG_FIGURE_NONE,
};

LTKTrace normalizeRotation(const LTKTrace &trace)
{
    if(trace.getNumberOfPoints() == 0)
        return trace;
    
    // find bounding box
    float minX = FLT_MAX, maxX = -FLT_MAX, minY = FLT_MAX, maxY = -FLT_MAX;
    for(int i = 0; i < trace.getNumberOfPoints(); i++)
    {
        floatVector pt;
        trace.getPointAt(i, pt);
        float x = pt[0], y = pt[1];
        if(x < minX) minX = x;
        if(x > maxX) maxX = x;
        if(y < minY) minY = y;
        if(y > maxY) maxY = y;
    }
    
    // find centroid of bounding box
    float centerX = (maxX-minX)/2, centerY = (maxY-minY)/2;
    
    // find angle of initial point from pi/2 (twelve o clock)
    floatVector initPt;
    trace.getPointAt(0, initPt);
    float initX = initPt[0], initY = initPt[1];
    float angle = atan2(initX-centerX, initY-centerY)-(M_PI/2.0);
    
    // rotation matrix to normalize to pi/2
    float rot = -angle;
    float rotMat[2][2] = {
        { cosf(rot), -sinf(rot) },
        { sinf(rot), cosf(rot) },
    };
    
    // apply rotation matrix
    LTKTrace rotated;
    for(int i = 0; i < trace.getNumberOfPoints(); i++)
    {
        floatVector pt;
        trace.getPointAt(i, pt);
        float x = pt[0], y = pt[1];
        float x_ = x*rotMat[0][0] + y*rotMat[0][1];
        float y_ = x*rotMat[1][0] + y*rotMat[1][1];
        pt[0] = x_; pt[1] = y_;
        rotated.addPoint(pt);
    }
    
    return rotated;
}

static AGHandwritingRecognizer * g_instance = NULL;

AGHandwritingRecognizer *AGHandwritingRecognizer::instance()
{
    if(g_instance == NULL)
        g_instance = new AGHandwritingRecognizer;
    return g_instance;
}

NSString *projectPath()
{
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
             objectAtIndex:0] stringByAppendingPathComponent:@"projects"];
}

void listRecursive(NSString *path, NSString *indent)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    
    NSError *error = NULL;
    NSArray *files = [manager contentsOfDirectoryAtPath:path error:&error];
    for(NSString *file in files)
    {
        NSString *fullPath = [path stringByAppendingPathComponent:file];
        NSDictionary *attributes = [manager attributesOfItemAtPath:fullPath error:&error];
        short permissions = [attributes[NSFilePosixPermissions] shortValue];
        
        BOOL canRead = [manager isReadableFileAtPath:fullPath];
        BOOL canWrite = [manager isWritableFileAtPath:fullPath];
        BOOL canExec = [manager isExecutableFileAtPath:fullPath];
        
        NSLog(@"%@%@ %o %s%s%s", indent, file, permissions, canRead?"r":"-", canWrite?"w":"-", canExec?"x":"-");
        BOOL isDir = NO;
        if([manager fileExistsAtPath:fullPath isDirectory:&isDir] && isDir)
            listRecursive(fullPath, [indent stringByAppendingString:@"- "]);
    }
}

AGHandwritingRecognizer::AGHandwritingRecognizer()
{
    if(![[NSFileManager defaultManager] fileExistsAtPath:projectPath()])
        this->_loadData();
    
    int iResult;
    
    // get util object
    _util = LTKOSUtilFactory::getInstance();
    
    // create engine
    _engine = createLTKLipiEngine();
    
    // set root path for projects
    _engine->setLipiRootPath([[projectPath() stringByDeletingLastPathComponent] UTF8String]);
    
    NSLog(@"project path: %@", projectPath());
    // [AGHandwritingRecognizer listRecursive:[[AGHandwritingRecognizer projectPath] stringByDeletingLastPathComponent] indent:@""];
    
    
    // initialize
    iResult = _engine->initializeLipiEngine();
    if(iResult != SUCCESS)
    {
        cout << iResult <<": Error initializing LipiEngine." << endl;
        NSLog(@"Error initializing LipiEngine (%i)", iResult);
        delete _util;
        _util = NULL;
        
        return;
    }
    
    // configure capture device settings
    LTKCaptureDevice captureDevice;
    // hopefully none of these values are important
    captureDevice.setSamplingRate(60); // guesstimate
    captureDevice.setXDPI(132); // basic ipad DPI
    captureDevice.setYDPI(132); // basic ipad DPI
    captureDevice.setLatency(0.01); // ballpark guess, is probably higher
    captureDevice.setUniformSampling(false);
    
    /* create shape recognizer */
    _shapeReco = NULL;
    string recoName = "SHAPEREC_SHAPES";
    _engine->createShapeRecognizer(recoName, &_shapeReco);
    if(_shapeReco == NULL)
    {
        cout << endl << "Error creating Shape Recognizer" << endl;
        NSLog(@"Error creating Shape Recognizer");
        delete _util;
        _util = NULL;
        
        return;
    }
    
    // load model data from disk
    iResult = _shapeReco->loadModelData();
    if(iResult != SUCCESS)
    {
        cout << endl << iResult << ": Error loading model data for Shape Recognizer" << endl;
        NSLog(@"Error loading model data for Shape Recognizer (%i)", iResult);
        _engine->deleteShapeRecognizer(_shapeReco);
        _shapeReco = NULL;
        delete _util;
        _util = NULL;
        
        return;
    }
    
    _shapeReco->setDeviceContext(captureDevice);
    
    
    /* create numeral recognizer */
    _numeralReco = NULL;
    recoName = "SHAPEREC_NUMERALS";
    _engine->createShapeRecognizer(recoName, &_numeralReco);
    if(_numeralReco == NULL)
    {
        cout << endl << "Error creating Numeral Recognizer" << endl;
        NSLog(@"Error creating Numeral Recognizer");
        delete _util;
        _util = NULL;
        
        return;
    }
    
    // load model data from disk
    iResult = _numeralReco->loadModelData();
    if(iResult != SUCCESS)
    {
        cout << endl << iResult << ": Error loading model data for Numeral Recognizer" << endl;
        _engine->deleteShapeRecognizer(_numeralReco);
        _numeralReco = NULL;
        NSLog(@"Error loading model data for Numeral Recognizer (%i)", iResult);
        delete _util;
        _util = NULL;
        
        return ;
    }
    
    _numeralReco->setDeviceContext(captureDevice);
}

AGHandwritingRecognizer::~AGHandwritingRecognizer()
{
    if(_util != NULL)
    {
        delete _util;
        _util = NULL;
    }
    
    if(_engine)
    {
        if(_shapeReco != NULL)
        {
            _engine->deleteShapeRecognizer(_shapeReco);
            _shapeReco = NULL;
        }
        
        _engine = NULL;
    }
}

void AGHandwritingRecognizer::setWindowFrame(GLvrectf frame)
{
    m_windowFrame = frame;
}

void AGHandwritingRecognizer::_loadData()
{
    NSLog(@"copying LipiTk model data");
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    [fileManager removeItemAtPath:projectPath() error:NULL];
    
//    [SSZipArchive unzipFileAtPath:[[NSBundle mainBundle] pathForResource:@"projects.zip" ofType:@""]
//                    toDestination:[[AGHandwritingRecognizer projectPath] stringByDeletingLastPathComponent]];
    NSError *error = NULL;
    NSString *projectSrcPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"projects"];
    NSString *projectDstPath = projectPath();
    [fileManager copyItemAtPath:projectSrcPath toPath:projectDstPath error:&error];
    if(error != NULL)
        NSLog(@"-[AGHandwritingRecognizer loadData]: error copying model data: %@", error.localizedDescription);
}


AGHandwritingRecognizerFigure AGHandwritingRecognizer::recognizeNumeral(const LTKTrace &trace)
{
	LTKScreenContext screenContext;
	vector<int> shapeSubset;
	int numChoices = 1;
	float confThreshold = 0.5f;
	vector<LTKShapeRecoResult> results;
	LTKTraceGroup traceGroup;
    
    screenContext.setBboxLeft(m_windowFrame.bl.x);
    screenContext.setBboxRight(m_windowFrame.br.x);
    screenContext.setBboxTop(m_windowFrame.ul.y);
    screenContext.setBboxBottom(m_windowFrame.bl.y);
    
    traceGroup.addTrace(trace);
    
	int iResult = _numeralReco->recognize(traceGroup, screenContext,
                                          shapeSubset, confThreshold,
                                          numChoices, results);
	if(iResult != SUCCESS)
	{
		cout << iResult << ": Error while recognizing." << endl;
        return AG_FIGURE_NONE;
	}
    
    if(results.size())
    {
        return g_figureForNumeralShape[results[0].getShapeId()];
    }
    
    // detect period
    const float PERIOD_AREA_MAX = 225;
    const int PERIOD_NUMPOINTS_MAX = 30;
    
    float minX = FLT_MAX, maxX = FLT_MIN, minY = FLT_MAX, maxY = FLT_MIN;
    for(int i = 0; i < trace.getNumberOfPoints(); i++)
    {
        floatVector p;
        trace.getPointAt(i, p);
        if(p[0] < minX) minX = p[0];
        if(p[0] > maxX) maxX = p[0];
        if(p[1] < minY) minY = p[1];
        if(p[1] > maxY) maxY = p[1];
    }
    
    float area = (maxX - minX)*(maxY - minY);
    
    if(area < PERIOD_AREA_MAX && trace.getNumberOfPoints() < PERIOD_NUMPOINTS_MAX)
        return AG_FIGURE_PERIOD;
//    fprintf(stderr, "area: %f number of points: %i\n", (maxX - minX)*(maxY - minY), trace.getNumberOfPoints());
    
    return AG_FIGURE_NONE;
}

void AGHandwritingRecognizer::addSampleForNumeral(const LTKTraceGroup &tg, AGHandwritingRecognizerFigure num)
{
    int shapeID = 0;
    while(g_figureForNumeralShape[shapeID] != num && g_figureForNumeralShape[shapeID] != AG_FIGURE_NONE)
        shapeID++;
    
    if(g_figureForNumeralShape[shapeID] != AG_FIGURE_NONE)
        _numeralReco->addSample(tg, shapeID);
}


AGHandwritingRecognizerFigure AGHandwritingRecognizer::recognizeShape(const LTKTrace &_trace)
{
	LTKScreenContext screenContext;
	vector<int> shapeSubset;
	int numChoices = 1;
	float confThreshold = 0.5f;
	vector<LTKShapeRecoResult> results;
	LTKTraceGroup traceGroup;
    
    screenContext.setBboxLeft(m_windowFrame.bl.x);
    screenContext.setBboxRight(m_windowFrame.br.x);
    screenContext.setBboxTop(m_windowFrame.ul.y);
    screenContext.setBboxBottom(m_windowFrame.bl.y);

    LTKTrace trace = normalizeRotation(_trace);
    traceGroup.addTrace(trace);

	int iResult = _shapeReco->recognize(traceGroup, screenContext,
                                        shapeSubset, confThreshold,
                                        numChoices, results);
	if(iResult != SUCCESS)
	{
		cout << iResult << ": Error while recognizing." << endl;
        return AG_FIGURE_NONE;
	}
    
    if(results.size())
    {
        return g_figureForShape[results[0].getShapeId()];
    }
    
    return AG_FIGURE_NONE;
}
