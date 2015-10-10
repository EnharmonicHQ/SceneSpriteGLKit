//
//  normalizeRotation.h
//  SceneSpriteGLKit
//
//  Created by Jonathan Saggau on 10/10/15.
//  Copyright © 2015 Enharmonic inc. All rights reserved.
//

#ifndef normalizeRotation_h
#define normalizeRotation_h

//Convenience function to normalize to +- pi
static inline void normalizeRotation(float *rotation)
{
    CGFloat juuuustALittleBiggerThanPi = M_PI;
    //http://www.cygnus-software.com/papers/comparingfloats/comparingfloats.htm
    (*(NSInteger *)&juuuustALittleBiggerThanPi) += 1;
    
    *rotation = fmod(*rotation, 2*M_PI);
    if (*rotation > juuuustALittleBiggerThanPi)
    {
        *rotation =  -(2*M_PI - *rotation) ;
    }
    else if (*rotation < -juuuustALittleBiggerThanPi)
    {
        *rotation = 2*M_PI + *rotation;
    }
}

#endif /* normalizeRotation_h */
