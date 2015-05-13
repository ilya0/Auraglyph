//
//  AGUserInterface.mm
//  Auragraph
//
//  Created by Spencer Salazar on 8/14/13.
//  Copyright (c) 2013 Spencer Salazar. All rights reserved.
//

#include "AGUserInterface.h"
#include "AGNode.h"
#include "AGAudioNode.h"
#include "AGGenericShader.h"
#include "AGHandwritingRecognizer.h"
#include "AGViewController.h"
#include "AGDef.h"
#include "AGStyle.h"

#include "TexFont.h"
#include "Texture.h"
#include "ES2Render.h"
#include "GeoGenerator.h"

#include <sstream>


static const float AGNODESELECTOR_RADIUS = 0.02;


//------------------------------------------------------------------------------
// ### AGUIStandardNodeEditor ###
//------------------------------------------------------------------------------
#pragma mark -
#pragma mark AGUIStandardNodeEditor

static const int NODEEDITOR_ROWCOUNT = 5;


bool AGUIStandardNodeEditor::s_init = false;
float AGUIStandardNodeEditor::s_radius = 0;
GLuint AGUIStandardNodeEditor::s_geoSize = 0;
GLvertex3f * AGUIStandardNodeEditor::s_geo = NULL;
GLuint AGUIStandardNodeEditor::s_boundingOffset = 0;
GLuint AGUIStandardNodeEditor::s_innerboxOffset = 0;
GLuint AGUIStandardNodeEditor::s_buttonBoxOffset = 0;
GLuint AGUIStandardNodeEditor::s_itemEditBoxOffset = 0;

void AGUIStandardNodeEditor::initializeNodeEditor()
{
    if(!s_init)
    {
        s_init = true;
        
        s_geoSize = 16;
        s_geo = new GLvertex3f[s_geoSize];
        
        s_radius = AGNODESELECTOR_RADIUS;
        float radius = s_radius;
        
        // outer box
        // stroke GL_LINE_STRIP + fill GL_TRIANGLE_FAN
        s_geo[0] = GLvertex3f(-radius, radius, 0);
        s_geo[1] = GLvertex3f(-radius, -radius, 0);
        s_geo[2] = GLvertex3f(radius, -radius, 0);
        s_geo[3] = GLvertex3f(radius, radius, 0);
        
        // inner selection box
        // stroke GL_LINE_STRIP + fill GL_TRIANGLE_FAN
        s_geo[4] = GLvertex3f(-radius*0.95, radius/NODEEDITOR_ROWCOUNT, 0);
        s_geo[5] = GLvertex3f(-radius*0.95, -radius/NODEEDITOR_ROWCOUNT, 0);
        s_geo[6] = GLvertex3f(radius*0.95, -radius/NODEEDITOR_ROWCOUNT, 0);
        s_geo[7] = GLvertex3f(radius*0.95, radius/NODEEDITOR_ROWCOUNT, 0);
        
        // button box
        // stroke GL_LINE_STRIP + fill GL_TRIANGLE_FAN
        s_geo[8] = GLvertex3f(-radius*0.9*0.60, radius/NODEEDITOR_ROWCOUNT * 0.95, 0);
        s_geo[9] = GLvertex3f(-radius*0.9*0.60, -radius/NODEEDITOR_ROWCOUNT * 0.95, 0);
        s_geo[10] = GLvertex3f(radius*0.9*0.60, -radius/NODEEDITOR_ROWCOUNT * 0.95, 0);
        s_geo[11] = GLvertex3f(radius*0.9*0.60, radius/NODEEDITOR_ROWCOUNT * 0.95, 0);
        
        // item edit bounding box
        // stroke GL_LINE_STRIP + fill GL_TRIANGLE_FAN
        s_geo[12] = GLvertex3f(-radius*1.05, radius, 0);
        s_geo[13] = GLvertex3f(-radius*1.05, -radius, 0);
        s_geo[14] = GLvertex3f(radius*3.45, -radius, 0);
        s_geo[15] = GLvertex3f(radius*3.45, radius, 0);
        
        s_boundingOffset = 0;
        s_innerboxOffset = 4;
        s_buttonBoxOffset = 8;
        s_itemEditBoxOffset = 12;
    }
}

AGUIStandardNodeEditor::AGUIStandardNodeEditor(AGNode *node) :
m_node(node),
m_hit(-1),
m_editingPort(-1),
m_t(0),
m_doneEditing(false),
m_hitAccept(false),
m_startedInAccept(false),
m_hitDiscard(false),
m_startedInDiscard(false),
m_lastTraceWasRecognized(true)
{
    initializeNodeEditor();
    
//    string ucname = m_node->title();
//    for(int i = 0; i < ucname.length(); i++) ucname[i] = toupper(ucname[i]);
//    m_title = "EDIT " + ucname;
    m_title = "EDIT";
}

void AGUIStandardNodeEditor::update(float t, float dt)
{
    m_modelView = AGNode::globalModelViewMatrix();
    GLKMatrix4 projection = AGNode::projectionMatrix();
    
    m_modelView = GLKMatrix4Translate(m_modelView, m_node->position().x, m_node->position().y, m_node->position().z);
    
    float squeezeHeight = AGStyle::open_squeezeHeight;
    float animTimeX = AGStyle::open_animTimeX;
    float animTimeY = AGStyle::open_animTimeY;
    
    if(m_t < animTimeX)
        m_modelView = GLKMatrix4Scale(m_modelView, squeezeHeight+(m_t/animTimeX)*(1-squeezeHeight), squeezeHeight, 1);
    else if(m_t < animTimeX+animTimeY)
        m_modelView = GLKMatrix4Scale(m_modelView, 1.0, squeezeHeight+((m_t-animTimeX)/animTimeY)*(1-squeezeHeight), 1);
    
    m_normalMatrix = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(m_modelView), NULL);
    
    m_modelViewProjectionMatrix = GLKMatrix4Multiply(projection, m_modelView);
    
    m_t += dt;
}

void AGUIStandardNodeEditor::render()
{
    TexFont *text = AGStyle::standardFont64();
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    /* draw bounding box */
    
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), s_geo);
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::white);
    glDisableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
    glDisableVertexAttribArray(GLKVertexAttribNormal);
    
    AGGenericShader::instance().useProgram();
    
    AGGenericShader::instance().setMVPMatrix(m_modelViewProjectionMatrix);
    AGGenericShader::instance().setNormalMatrix(m_normalMatrix);
    
//    AGClipShader &shader = AGClipShader::instance();
//    
//    shader.useProgram();
//    
//    shader.setMVPMatrix(m_modelViewProjectionMatrix);
//    shader.setNormalMatrix(m_normalMatrix);
//    shader.setClip(GLvertex2f(-m_radius, -m_radius), GLvertex2f(m_radius*2, m_radius*2));
//    shader.setLocalMatrix(GLKMatrix4Identity);
//    
//    GLKMatrix4 localMatrix;
    
    // stroke
    glLineWidth(4.0f);
    glDrawArrays(GL_LINE_LOOP, s_boundingOffset, 4);
    
    GLcolor4f blackA = GLcolor4f(0, 0, 0, 0.75);
    glVertexAttrib4fv(GLKVertexAttribColor, (const float*) &blackA);
    
    // fill
    glDrawArrays(GL_TRIANGLE_FAN, s_boundingOffset, 4);
    
    
    /* draw title */
    
    float rowCount = NODEEDITOR_ROWCOUNT;
    GLKMatrix4 proj = AGNode::projectionMatrix();
    
    GLKMatrix4 titleMV = GLKMatrix4Translate(m_modelView, -s_radius*0.9, s_radius - s_radius*2.0/rowCount, 0);
    titleMV = GLKMatrix4Scale(titleMV, 0.61, 0.61, 0.61);
    text->render(m_title, GLcolor4f::white, titleMV, proj);
    
    
    /* draw items */

    int numPorts = m_node->numEditPorts();
    
    for(int i = 0; i < numPorts; i++)
    {
        float y = s_radius - s_radius*2.0*(i+2)/rowCount;
        GLcolor4f nameColor(0.61, 0.61, 0.61, 1);
        GLcolor4f valueColor = GLcolor4f::white;
    
        if(i == m_hit)
        {
            glBindVertexArrayOES(0);
            glBindBuffer(GL_ARRAY_BUFFER, 0);
            
            /* draw hit box */
            
            glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), s_geo);
            glEnableVertexAttribArray(GLKVertexAttribPosition);
            glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::white);
            glDisableVertexAttribArray(GLKVertexAttribColor);
            glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
            glDisableVertexAttribArray(GLKVertexAttribNormal);
            
            AGGenericShader::instance().useProgram();
            GLKMatrix4 hitMVP = GLKMatrix4Multiply(proj, GLKMatrix4Translate(m_modelView, 0, y + s_radius/rowCount, 0));
            AGGenericShader::instance().setMVPMatrix(hitMVP);
            AGGenericShader::instance().setNormalMatrix(m_normalMatrix);
            
            // fill
            glDrawArrays(GL_TRIANGLE_FAN, s_innerboxOffset, 4);
            
            // invert colors
            nameColor = GLcolor4f(1-nameColor.r, 1-nameColor.g, 1-nameColor.b, 1);
            valueColor = GLcolor4f(1-valueColor.r, 1-valueColor.g, 1-valueColor.b, 1);
        }
        
        GLKMatrix4 nameMV = GLKMatrix4Translate(m_modelView, -s_radius*0.9, y + s_radius/rowCount*0.1, 0);
        nameMV = GLKMatrix4Scale(nameMV, 0.61, 0.61, 0.61);
        text->render(m_node->editPortInfo(i).name, nameColor, nameMV, proj);
        
        GLKMatrix4 valueMV = GLKMatrix4Translate(m_modelView, s_radius*0.1, y + s_radius/rowCount*0.1, 0);
        valueMV = GLKMatrix4Scale(valueMV, 0.61, 0.61, 0.61);
        std::stringstream ss;
        float v = 0;
        m_node->getEditPortValue(i, v);
        ss << v;
        text->render(ss.str(), valueColor, valueMV, proj);
    }
    
    
    /* draw item editor */
    
    if(m_editingPort >= 0)
    {
        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), s_geo);
        glEnableVertexAttribArray(GLKVertexAttribPosition);
        glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::white);
        glDisableVertexAttribArray(GLKVertexAttribColor);
        glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
        glDisableVertexAttribArray(GLKVertexAttribNormal);
        
        float y = s_radius - s_radius*2.0*(m_editingPort+2)/rowCount;
        
        AGGenericShader::instance().useProgram();
        AGGenericShader::instance().setNormalMatrix(m_normalMatrix);
        
        // bounding box
        GLKMatrix4 bbMVP = GLKMatrix4Multiply(proj, GLKMatrix4Translate(m_modelView, 0, y - s_radius + s_radius*2/rowCount, 0));
        AGGenericShader::instance().setMVPMatrix(bbMVP);
        
        // stroke
        glDrawArrays(GL_LINE_LOOP, s_itemEditBoxOffset, 4);
        
        glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &blackA);
        
        // fill
        glDrawArrays(GL_TRIANGLE_FAN, s_itemEditBoxOffset, 4);
        
        
        glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::white);

        // accept button
        GLKMatrix4 buttonMVP = GLKMatrix4Multiply(proj, GLKMatrix4Translate(m_modelView, s_radius*1.65, y + s_radius/rowCount, 0));
        AGGenericShader::instance().setMVPMatrix(buttonMVP);
        if(m_hitAccept)
            // stroke
            glDrawArrays(GL_LINE_LOOP, s_buttonBoxOffset, 4);
        else
            // fill
            glDrawArrays(GL_TRIANGLE_FAN, s_buttonBoxOffset, 4);
        
        // discard button
        buttonMVP = GLKMatrix4Multiply(proj, GLKMatrix4Translate(m_modelView, s_radius*1.65 + s_radius*1.2, y + s_radius/rowCount, 0));
        AGGenericShader::instance().setMVPMatrix(buttonMVP);
        // fill
        if(m_hitDiscard)
            // stroke
            glDrawArrays(GL_LINE_LOOP, s_buttonBoxOffset, 4);
        else
            // fill
            glDrawArrays(GL_TRIANGLE_FAN, s_buttonBoxOffset, 4);
        
        // text
        GLKMatrix4 textMV = GLKMatrix4Translate(m_modelView, s_radius*1.2, y + s_radius/rowCount*0.1, 0);
        textMV = GLKMatrix4Scale(textMV, 0.5, 0.5, 0.5);
        if(m_hitAccept)
            text->render("Accept", GLcolor4f::white, textMV, proj);
        else
            text->render("Accept", GLcolor4f::black, textMV, proj);
        
        
        textMV = GLKMatrix4Translate(m_modelView, s_radius*1.2 + s_radius*1.2, y + s_radius/rowCount*0.1, 0);
        textMV = GLKMatrix4Scale(textMV, 0.5, 0.5, 0.5);
        if(m_hitDiscard)
            text->render("Discard", GLcolor4f::white, textMV, proj);
        else
            text->render("Discard", GLcolor4f::black, textMV, proj);
        
        // text name + value
        GLKMatrix4 nameMV = GLKMatrix4Translate(m_modelView, -s_radius*0.9, y + s_radius/rowCount*0.1, 0);
        nameMV = GLKMatrix4Scale(nameMV, 0.61, 0.61, 0.61);
        text->render(m_node->editPortInfo(m_editingPort).name, GLcolor4f::white, nameMV, proj);
        
        GLKMatrix4 valueMV = GLKMatrix4Translate(m_modelView, s_radius*0.1, y + s_radius/rowCount*0.1, 0);
        valueMV = GLKMatrix4Scale(valueMV, 0.61, 0.61, 0.61);
        std::stringstream ss;
        ss << m_currentValue;
        if(m_decimal && floorf(m_currentValue) == m_currentValue) ss << "."; // show decimal point if user has drawn it
        text->render(ss.str(), GLcolor4f::white, valueMV, proj);
        
        AGGenericShader::instance().useProgram();
        AGGenericShader::instance().setNormalMatrix(m_normalMatrix);
        AGGenericShader::instance().setMVPMatrix(GLKMatrix4Multiply(proj, AGNode::globalModelViewMatrix()));

        // draw traces
        for(std::list<std::vector<GLvertex3f> >::iterator i = m_drawline.begin(); i != m_drawline.end(); i++)
        {
            std::vector<GLvertex3f> geo = *i;
            glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), geo.data());
            glEnableVertexAttribArray(GLKVertexAttribPosition);
            glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::white);
            glDisableVertexAttribArray(GLKVertexAttribColor);
            glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
            glDisableVertexAttribArray(GLKVertexAttribNormal);
            
            glDrawArrays(GL_LINE_STRIP, 0, geo.size());
        }
    }
}


int AGUIStandardNodeEditor::hitTest(const GLvertex3f &t, bool *inBbox)
{
    float rowCount = NODEEDITOR_ROWCOUNT;
    
    *inBbox = false;
    
    GLvertex3f pos = m_node->position();
    
    if(m_editingPort >= 0)
    {
        float y = s_radius - s_radius*2.0*(m_editingPort+2)/rowCount;
        
        float bb_center = y - s_radius + s_radius*2/rowCount;
        if(t.x > pos.x+s_geo[s_itemEditBoxOffset].x && t.x < pos.x+s_geo[s_itemEditBoxOffset+2].x &&
           t.y > pos.y+bb_center+s_geo[s_itemEditBoxOffset+2].y && t.y < pos.y+bb_center+s_geo[s_itemEditBoxOffset].y)
        {
            *inBbox = true;
            
            GLvertex3f acceptCenter = pos + GLvertex3f(s_radius*1.65, y + s_radius/rowCount, pos.z);
            GLvertex3f discardCenter = pos + GLvertex3f(s_radius*1.65 + s_radius*1.2, y + s_radius/rowCount, pos.z);
            
            if(t.x > acceptCenter.x+s_geo[s_buttonBoxOffset].x && t.x < acceptCenter.x+s_geo[s_buttonBoxOffset+2].x &&
               t.y > acceptCenter.y+s_geo[s_buttonBoxOffset+2].y && t.y < acceptCenter.y+s_geo[s_buttonBoxOffset].y)
                return 1;
            if(t.x > discardCenter.x+s_geo[s_buttonBoxOffset].x && t.x < discardCenter.x+s_geo[s_buttonBoxOffset+2].x &&
               t.y > discardCenter.y+s_geo[s_buttonBoxOffset+2].y && t.y < discardCenter.y+s_geo[s_buttonBoxOffset].y)
                return 0;
        }
    }
    
    // check if in entire bounds
    else if(t.x > pos.x-s_radius && t.x < pos.x+s_radius &&
            t.y > pos.y-s_radius && t.y < pos.y+s_radius)
    {
        *inBbox = true;
        
        int numPorts = m_node->numEditPorts();
        
        for(int i = 0; i < numPorts; i++)
        {
            float y_max = pos.y + s_radius - s_radius*2.0*(i+1)/rowCount;
            float y_min = pos.y + s_radius - s_radius*2.0*(i+2)/rowCount;
            if(t.y > y_min && t.y < y_max)
            {
                return i;
            }
        }
    }
    
    return -1;
}

void AGUIStandardNodeEditor::touchDown(const AGTouchInfo &t)
{
    touchDown(t.position, t.screenPosition);
}

void AGUIStandardNodeEditor::touchMove(const AGTouchInfo &t)
{
    touchMove(t.position, t.screenPosition);
}

void AGUIStandardNodeEditor::touchUp(const AGTouchInfo &t)
{
    touchUp(t.position, t.screenPosition);
}


void AGUIStandardNodeEditor::touchDown(const GLvertex3f &t, const CGPoint &screen)
{
    if(m_editingPort < 0)
    {
        m_hit = -1;
        bool inBBox = false;
        
        // check if in entire bounds
        m_hit = hitTest(t, &inBBox);
        
        m_doneEditing = !inBBox;
    }
    else
    {
        m_hitAccept = false;
        m_startedInAccept = false;
        m_hitDiscard = false;
        m_startedInDiscard = false;
        
        bool inBBox = false;
        int hit = hitTest(t, &inBBox);
        
        if(hit == 0)
        {
            m_hitDiscard = true;
            m_startedInDiscard = true;
        }
        else if(hit == 1)
        {
            m_hitAccept = true;
            m_startedInAccept = true;
        }
        else if(inBBox)
        {
            if(!m_lastTraceWasRecognized && m_drawline.size())
                m_drawline.remove(m_drawline.back());
            m_drawline.push_back(std::vector<GLvertex3f>());
            m_currentTrace = LTKTrace();
            
            m_drawline.back().push_back(t);
            floatVector point;
            point.push_back(screen.x);
            point.push_back(screen.y);
            m_currentTrace.addPoint(point);
        }
    }
}

void AGUIStandardNodeEditor::touchMove(const GLvertex3f &t, const CGPoint &screen)
{
    if(!m_doneEditing)
    {
        if(m_editingPort >= 0)
        {
            bool inBBox = false;
            int hit = hitTest(t, &inBBox);
            
            m_hitAccept = false;
            m_hitDiscard = false;
            
            if(hit == 0 && m_startedInDiscard)
            {
                m_hitDiscard = true;
            }
            else if(hit == 1 && m_startedInAccept)
            {
                m_hitAccept = true;
            }
            else if(inBBox && !m_startedInDiscard && !m_startedInAccept)
            {
                m_drawline.back().push_back(t);
                floatVector point;
                point.push_back(screen.x);
                point.push_back(screen.y);
                m_currentTrace.addPoint(point);
            }
        }
        else
        {
            bool inBBox = false;
            m_hit = hitTest(t, &inBBox);
        }
    }
}

void AGUIStandardNodeEditor::touchUp(const GLvertex3f &t, const CGPoint &screen)
{
    if(!m_doneEditing)
    {
        if(m_editingPort >= 0)
        {
            if(m_hitAccept)
            {
//                m_doneEditing = true;
                m_node->setEditPortValue(m_editingPort, m_currentValue);
                m_editingPort = -1;
                m_hitAccept = false;
                m_drawline.clear();
            }
            else if(m_hitDiscard)
            {
//                m_doneEditing = true;
                m_editingPort = -1;
                m_hitDiscard = false;
                m_drawline.clear();
            }
            else if(m_currentTrace.getNumberOfPoints() > 0 && !m_startedInDiscard && !m_startedInAccept)
            {
                // attempt recognition
                AGHandwritingRecognizerFigure figure = [[AGHandwritingRecognizer instance] recognizeNumeral:m_currentTrace];
                
                switch(figure)
                {
                    case AG_FIGURE_0:
                    case AG_FIGURE_1:
                    case AG_FIGURE_2:
                    case AG_FIGURE_3:
                    case AG_FIGURE_4:
                    case AG_FIGURE_5:
                    case AG_FIGURE_6:
                    case AG_FIGURE_7:
                    case AG_FIGURE_8:
                    case AG_FIGURE_9:
                        if(m_decimal)
                        {
                            m_currentValue = m_currentValue + (figure-'0')*m_decimalFactor;
                            m_decimalFactor *= 0.1;
                        }
                        else
                            m_currentValue = m_currentValue*10 + (figure-'0');
                        m_lastTraceWasRecognized = true;
                        break;
                        
                    case AG_FIGURE_PERIOD:
                        if(m_decimal)
                            m_lastTraceWasRecognized = false;
                        else
                        {
                            m_decimalFactor = 0.1;
                            m_lastTraceWasRecognized = true;
                            m_decimal = true;
                        }
                        break;
                        
                    default:
                        m_lastTraceWasRecognized = false;
                }
            }
        }
        else
        {
            bool inBBox = false;
            m_hit = hitTest(t, &inBBox);
            
            if(m_hit >= 0)
            {
                m_editingPort = m_hit;
                m_hit = -1;
                m_currentValue = 0;
                m_decimal = false;
                m_drawline.clear();
                //m_node->getEditPortValue(m_editingPort, m_currentValue);
            }
        }
    }
}

GLvrectf AGUIStandardNodeEditor::effectiveBounds()
{
    if(m_editingPort >= 0)
    {
        // TODO HACK: overestimate bounds
        // because figuring out the item editor box bounds is too hard right now
        GLvertex2f size = GLvertex2f(s_radius*2, s_radius*2);
        return GLvrectf(m_node->position()-size, m_node->position()+size);
    }
    else
    {
        GLvertex2f size = GLvertex2f(s_radius, s_radius);
        return GLvrectf(m_node->position()-size, m_node->position()+size);
    }
}

//------------------------------------------------------------------------------
// ### AGUIButton ###
//------------------------------------------------------------------------------
#pragma mark - AGUIButton

AGUIButton::AGUIButton(const std::string &title, const GLvertex3f &pos, const GLvertex3f &size) :
m_action(nil)
{
    m_hit = m_hitOnTouchDown = m_latch = false;
    m_interactionType = INTERACTION_UPDOWN;
    
    m_title = title;
    
    m_pos = pos;
    m_size = size;
    m_geo[0] = GLvertex3f(0, 0, 0);
    m_geo[1] = GLvertex3f(size.x, 0, 0);
    m_geo[2] = GLvertex3f(size.x, size.y, 0);
    m_geo[3] = GLvertex3f(0, size.y, 0);
    
    float stripeInset = 0.0002;
    
    m_geo[4] = GLvertex3f(stripeInset, stripeInset, 0);
    m_geo[5] = GLvertex3f(size.x-stripeInset, stripeInset, 0);
    m_geo[6] = GLvertex3f(size.x-stripeInset, size.y-stripeInset, 0);
    m_geo[7] = GLvertex3f(stripeInset, size.y-stripeInset, 0);
}

AGUIButton::~AGUIButton()
{
    if(m_action != nil) Block_release(m_action);
    m_action = nil;
}

void AGUIButton::update(float t, float dt)
{
}

void AGUIButton::render()
{
    TexFont *text = AGStyle::standardFont64();
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    float textScale = 0.5;
    
    GLKMatrix4 proj = AGNode::projectionMatrix();
    GLKMatrix4 modelView = GLKMatrix4Translate(AGNode::globalModelViewMatrix(), m_pos.x, m_pos.y, m_pos.z);
    GLKMatrix4 textMV = GLKMatrix4Translate(modelView, m_size.x/2-text->width(m_title)*textScale/2, m_size.y/2-text->height()*textScale/2*1.25, 0);
//    GLKMatrix4 textMV = modelView;
    textMV = GLKMatrix4Scale(textMV, textScale, textScale, textScale);
    
    AGGenericShader &shader = AGGenericShader::instance();
    
    shader.useProgram();
    
    shader.setProjectionMatrix(proj);
    shader.setModelViewMatrix(modelView);
    shader.setNormalMatrix(GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelView), NULL));
    
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), m_geo);
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    
    glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::white);
    glDisableVertexAttribArray(GLKVertexAttribColor);
    
    glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
    glDisableVertexAttribArray(GLKVertexAttribNormal);
    
    if(isPressed())
    {
        glLineWidth(4.0);
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
        
        text->render(m_title, AGStyle::darkColor(), textMV, proj);
    }
    else
    {
        glDrawArrays(GL_LINE_LOOP, 0, 4);
        
        glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &GLcolor4f::black);
        glLineWidth(2.0);
        glDrawArrays(GL_LINE_LOOP, 4, 4);

        text->render(m_title, AGStyle::lightColor(), textMV, proj);
    }
}


void AGUIButton::touchDown(const GLvertex3f &t)
{
    m_hit = true;
    m_hitOnTouchDown = true;
    
    if(m_interactionType == INTERACTION_LATCH)
    {
        m_latch = !m_latch;
        if(m_action)
            m_action();
    }
}

void AGUIButton::touchMove(const GLvertex3f &t)
{
    m_hit = (m_hitOnTouchDown && hitTest(t) == this);
}

void AGUIButton::touchUp(const GLvertex3f &t)
{
    if(m_interactionType == INTERACTION_UPDOWN && m_hit && m_action)
        m_action();
    
    m_hit = false;
}

GLvrectf AGUIButton::effectiveBounds()
{
    return GLvrectf(m_pos, m_pos+m_size);
}

void AGUIButton::setAction(void (^action)())
{
    m_action = action;
}

bool AGUIButton::isPressed()
{
    if(m_interactionType == INTERACTION_UPDOWN)
        return m_hit;
    else
        return m_latch;
}


//------------------------------------------------------------------------------
// ### AGUITextButton ###
//------------------------------------------------------------------------------
#pragma mark - AGUITextButton

void AGUITextButton::render()
{
    TexFont *text = AGStyle::standardFont64();

    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    float textScale = 1;
    
    GLKMatrix4 proj = AGNode::projectionMatrix();
    GLKMatrix4 modelView = GLKMatrix4Translate(AGNode::fixedModelViewMatrix(), m_pos.x, m_pos.y, m_pos.z);
    GLKMatrix4 textMV = GLKMatrix4Translate(modelView, m_size.x/2-text->width(m_title)*textScale/2, m_size.y/2-text->height()*textScale/2*1.25, 0);
    //    GLKMatrix4 textMV = modelView;
    textMV = GLKMatrix4Scale(textMV, textScale, textScale, textScale);
    
    if(isPressed())
    {
        AGGenericShader &shader = AGGenericShader::instance();
        
        shader.useProgram();
        
        shader.setProjectionMatrix(proj);
        shader.setModelViewMatrix(modelView);
        shader.setNormalMatrix(GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelView), NULL));
        
        glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), m_geo);
        glEnableVertexAttribArray(GLKVertexAttribPosition);
        
        glVertexAttrib4fv(GLKVertexAttribColor, (const float *) &AGStyle::lightColor());
        glDisableVertexAttribArray(GLKVertexAttribColor);
        
        glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
        glDisableVertexAttribArray(GLKVertexAttribNormal);
        
        glLineWidth(4.0);
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
    }
    
    text->render(m_title, AGStyle::lightColor(), textMV, proj);
}


//------------------------------------------------------------------------------
// ### AGUIIconButton ###
//------------------------------------------------------------------------------
#pragma mark - AGUIIconButton
AGUIIconButton::AGUIIconButton(const GLvertex3f &pos, const GLvertex2f &size, AGRenderInfoV iconRenderInfo) :
AGUIButton("", pos, size),
m_iconInfo(iconRenderInfo)
{
    m_boxGeo = NULL;
    setIconMode(ICONMODE_SQUARE);
    
    m_boxInfo.color = AGStyle::lightColor();
    m_renderList.push_back(&m_boxInfo);
    
    m_renderList.push_back(&m_iconInfo);
}

void AGUIIconButton::setIconMode(AGUIIconButton::IconMode m)
{
    m_iconMode = m;
    
    if(m_iconMode == ICONMODE_SQUARE)
    {
        SAFE_DELETE_ARRAY(m_boxGeo);
        
        m_boxGeo = new GLvertex3f[4];
        GeoGen::makeRect(m_boxGeo, m_size.x, m_size.y);
        
        m_boxInfo.geo = m_boxGeo;
        m_boxInfo.geoType = GL_TRIANGLE_FAN;
        m_boxInfo.numVertex = 4;
    }
    else if (m_iconMode == ICONMODE_CIRCLE)
    {
        SAFE_DELETE_ARRAY(m_boxGeo);
        
        m_boxGeo = new GLvertex3f[32];
        GeoGen::makeCircle(m_boxGeo, 32, m_size.x/2);
        
        m_boxInfo.geo = m_boxGeo;
        m_boxInfo.geoType = GL_LINE_LOOP;
        m_boxInfo.numVertex = 32;
        m_boxInfo.geoOffset = 1;
    }
}

AGUIIconButton::IconMode AGUIIconButton::getIconMode()
{
    return m_iconMode;
}

void AGUIIconButton::update(float t, float dt)
{
    AGInteractiveObject::update(t, dt);
    
    GLKMatrix4 parentModelview;
    if(m_parent) parentModelview = m_parent->m_renderState.modelview;
    else if(renderFixed()) parentModelview = AGRenderObject::fixedModelViewMatrix();
    else parentModelview = AGRenderObject::globalModelViewMatrix();
    
    m_renderState.modelview = GLKMatrix4Translate(parentModelview, m_pos.x, m_pos.y, m_pos.z);
    m_renderState.normal = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(m_renderState.modelview), NULL);
    
    if(isPressed())
    {
        m_iconInfo.color = AGStyle::darkColor();
        m_boxInfo.geoType = GL_TRIANGLE_FAN;
        m_boxInfo.geoOffset = 0;
        m_boxInfo.numVertex = (m_iconMode == ICONMODE_CIRCLE ? 32 : 4);
    }
    else
    {
        m_iconInfo.color = AGStyle::lightColor();
        m_boxInfo.geoType = GL_LINE_LOOP;
        m_boxInfo.geoOffset = (m_iconMode == ICONMODE_CIRCLE ? 1 : 0);
        m_boxInfo.numVertex = (m_iconMode == ICONMODE_CIRCLE ? 31 : 4);
    }
}

void AGUIIconButton::render()
{
    // bypass AGUIButton::render()
    
    glLineWidth(1.0);

    AGInteractiveObject::render();
}


//------------------------------------------------------------------------------
// ### AGUITrash ###
//------------------------------------------------------------------------------
#pragma mark - AGUITrash

AGUITrash &AGUITrash::instance()
{
    static AGUITrash s_trash;
    
    return s_trash;
}

AGUITrash::AGUITrash()
{
    m_tex = loadOrRetrieveTexture(@"trash.png");
    
    m_radius = 0.005;
    m_geo[0] = GLvertex3f(-m_radius, -m_radius, 0);
    m_geo[1] = GLvertex3f( m_radius, -m_radius, 0);
    m_geo[2] = GLvertex3f(-m_radius,  m_radius, 0);
    m_geo[3] = GLvertex3f( m_radius,  m_radius, 0);
    
    m_uv[0] = GLvertex2f(0, 0);
    m_uv[1] = GLvertex2f(1, 0);
    m_uv[2] = GLvertex2f(0, 1);
    m_uv[3] = GLvertex2f(1, 1);
    
    m_active = false;

    m_scale.value = 0.5;
    m_scale.target = 1;
    m_scale.slew = 0.1;
}

AGUITrash::~AGUITrash()
{
    
}

void AGUITrash::update(float t, float dt)
{
    if(m_active)
        m_scale = 1.25;
    else
        m_scale = 1;
    
    m_scale.interp();
}

void AGUITrash::render()
{
    GLKMatrix4 proj = AGNode::projectionMatrix();
    GLKMatrix4 modelView = GLKMatrix4Translate(AGNode::fixedModelViewMatrix(), m_position.x, m_position.y, m_position.z);
    modelView = GLKMatrix4Scale(modelView, m_scale, m_scale, m_scale);
    
    AGGenericShader &shader = AGTextureShader::instance();
    
    shader.useProgram();
    
    shader.setProjectionMatrix(proj);
    shader.setModelViewMatrix(modelView);
    shader.setNormalMatrix(GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelView), NULL));
    
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(GLvertex3f), m_geo);
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    
    glVertexAttrib3f(GLKVertexAttribNormal, 0, 0, 1);
    if(m_active)
        glVertexAttrib4fv(GLKVertexAttribColor, (const GLfloat *) &GLcolor4f::red);
    else
        glVertexAttrib4fv(GLKVertexAttribColor, (const GLfloat *) &GLcolor4f::white);
    
    glEnable(GL_TEXTURE_2D);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_tex);
    glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, sizeof(GLvertex2f), m_uv);
    glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

void AGUITrash::touchDown(const GLvertex3f &t)
{
    
}

void AGUITrash::touchMove(const GLvertex3f &t)
{
    
}

void AGUITrash::touchUp(const GLvertex3f &t)
{
    
}

AGUIObject *AGUITrash::hitTest(const GLvertex3f &t)
{
    // point in circle
    if((t-m_position).magnitudeSquared() < m_radius*m_radius)
        return this;
    return NULL;
}

void AGUITrash::activate()
{
    m_active = true;
}

void AGUITrash::deactivate()
{
    m_active = false;
}




