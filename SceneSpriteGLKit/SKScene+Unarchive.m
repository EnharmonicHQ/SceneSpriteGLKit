//
//  SKScene+Unarchive.m
//  SceneSpriteGLKit
//
//  Created by Jonathan Saggau on 10/10/15.
//  Copyright © 2015 Enharmonic inc. All rights reserved.
//

#import "SKScene+Unarchive.h"

@implementation SKScene (Unarchive)

+(instancetype)unarchiveFromFile:(NSString *)file
{
    /* Retrieve scene file path from the application bundle */
    NSString *nodePath = [[NSBundle mainBundle] pathForResource:file ofType:@"sks"];
    /* Unarchive the file to an SKScene object */
    NSData *data = [NSData dataWithContentsOfFile:nodePath
                                          options:NSDataReadingMappedIfSafe
                                            error:nil];
    NSKeyedUnarchiver *arch = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [arch setClass:self forClassName:@"SKScene"];
    SKScene *scene = [arch decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    [arch finishDecoding];
    
    return scene;
}

@end
