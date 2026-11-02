//
//  TemporarySettings.m
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "TemporarySettings.h"
#import "OnScreenControls.h"

@implementation TemporarySettings

- (id) initFromSettings:(Settings*)settings {
    self = [self init];
    
    self.parent = settings;
    
#if TARGET_OS_TV
    // Apply default values from our Root.plist
    NSString* settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    NSDictionary* settingsData = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray* preferences = [settingsData objectForKey:@"PreferenceSpecifiers"];
    // Stream settings moved to the in-app panel, so their defaults live here
    NSMutableDictionary* defaultsToRegister = [@{@"streamResolution": @4, @"framerate": @60, @"bitrate": @0,
                                                 @"enableHdr": @NO, @"statsOverlay": @NO, @"btMouseSupport": @NO} mutableCopy];
    for (NSDictionary* prefSpecification in preferences) {
        NSString* key = [prefSpecification objectForKey:@"Key"];
        if (key != nil) {
            [defaultsToRegister setObject:[prefSpecification objectForKey:@"DefaultValue"] forKey:key];
        }
    }
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsToRegister];
    
    self.bitrate = [NSNumber numberWithInteger:[[NSUserDefaults standardUserDefaults] integerForKey:@"bitrate"]];
    self.framerate = [NSNumber numberWithInteger:[[NSUserDefaults standardUserDefaults] integerForKey:@"framerate"]];
    assert([self.framerate intValue] != 0);
    self.audioConfig = [NSNumber numberWithInteger:[[NSUserDefaults standardUserDefaults] integerForKey:@"audioConfig"]];
    assert([self.audioConfig intValue] != 0);
    self.preferredCodec = (typeof(self.preferredCodec))[[NSUserDefaults standardUserDefaults] integerForKey:@"preferredCodec"];
    self.useFramePacing = [[NSUserDefaults standardUserDefaults] integerForKey:@"useFramePacing"] != 0;
    self.playAudioOnPC = [[NSUserDefaults standardUserDefaults] boolForKey:@"audioOnPC"];
    self.enableHdr = [[NSUserDefaults standardUserDefaults] boolForKey:@"enableHdr"];
    self.optimizeGames = [[NSUserDefaults standardUserDefaults] boolForKey:@"optimizeGames"];
    self.multiController = [[NSUserDefaults standardUserDefaults] boolForKey:@"multipleControllers"];
    self.swapABXYButtons = [[NSUserDefaults standardUserDefaults] boolForKey:@"swapABXYButtons"];
    self.btMouseSupport = [[NSUserDefaults standardUserDefaults] boolForKey:@"btMouseSupport"];
    self.statsOverlay = [[NSUserDefaults standardUserDefaults] boolForKey:@"statsOverlay"];
    
    NSInteger _screenSize = [[NSUserDefaults standardUserDefaults] integerForKey:@"streamResolution"];
    switch (_screenSize) {
        case 0:
            self.height = [NSNumber numberWithInteger:720];
            self.width = [NSNumber numberWithInteger:1280];
            break;
        case 1:
            self.height = [NSNumber numberWithInteger:1080];
            self.width = [NSNumber numberWithInteger:1920];
            break;
        case 2:
            self.height = [NSNumber numberWithInteger:2160];
            self.width = [NSNumber numberWithInteger:3840];
            break;
        case 3:
            self.height = [NSNumber numberWithInteger:1440];
            self.width = [NSNumber numberWithInteger:2560];
            break;
        case 4: {
            // Match TV: the screen's native resolution, capped at 4K
            CGSize native = [UIScreen mainScreen].nativeBounds.size;
            BOOL uhd = MAX(native.width, native.height) >= 3840;
            self.height = [NSNumber numberWithInteger:uhd ? 2160 : 1080];
            self.width = [NSNumber numberWithInteger:uhd ? 3840 : 1920];
            break;
        }
        default:
            abort();
    }
    
    // Automatic bitrate: 20 Mbps for 1080p60, scaled by pixels per second
    if ([self.bitrate intValue] == 0) {
        double scale = ([self.width doubleValue] * [self.height doubleValue] * [self.framerate doubleValue]) / (1920.0 * 1080.0 * 60.0);
        self.bitrate = [NSNumber numberWithInt:MIN(150000, MAX(5000, (int)(20000 * scale)))];
    }
    self.onscreenControls = [NSNumber numberWithInteger:OnScreenControlsLevelOff];
#else
    self.bitrate = settings.bitrate;
    self.framerate = settings.framerate;
    self.height = settings.height;
    self.width = settings.width;
    self.audioConfig = settings.audioConfig;
    self.preferredCodec = settings.preferredCodec;
    self.useFramePacing = settings.useFramePacing;
    self.playAudioOnPC = settings.playAudioOnPC;
    self.enableHdr = settings.enableHdr;
    self.optimizeGames = settings.optimizeGames;
    self.multiController = settings.multiController;
    self.swapABXYButtons = settings.swapABXYButtons;
    self.onscreenControls = settings.onscreenControls;
    self.btMouseSupport = settings.btMouseSupport;
    self.absoluteTouchMode = settings.absoluteTouchMode;
    self.statsOverlay = settings.statsOverlay;
#endif
    self.uniqueId = settings.uniqueId;
    
    return self;
}

@end
