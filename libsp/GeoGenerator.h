//
//  GeoGenerator.h
//  Auragraph
//
//  Created by Spencer Salazar on 10/21/14.
//  Copyright (c) 2014 Spencer Salazar. All rights reserved.
//

#ifndef Auragraph_GeoGenerator_h
#define Auragraph_GeoGenerator_h

#include "Geometry.h"
#include <math.h>


namespace GeoGen
{
    /* makeCircle()
     - Generate vertices for circle centered at (0,0,0) and with specified radius
     - points must have sufficient
     - Draw as stroke with GL_LINE_LOOP (skip the first vertex)
     or fill with GL_TRIANGLE_FAN
     */
    void makeCircle(GLvertex3f *points, int numPoints, float radius);
    
    /* circle64()
     - Return 64 vertex circle, created a la makeCircle() above
     - radius = 1
     */
    GLvertex3f *circle64();
    
}


#endif