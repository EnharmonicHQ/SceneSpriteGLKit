//
//  SKScene+Unarchive.h
//  SceneSpriteGLKit
//
//  Created by Jonathan Saggau on 10/10/15.
//  Copyright © 2015 Enharmonic inc. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>

@interface SKScene (Unarchive)

+(instancetype)unarchiveFromFile:(NSString *)file;

@end
