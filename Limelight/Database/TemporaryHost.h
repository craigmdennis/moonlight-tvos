//
//  TemporaryHost.h
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//

#import "Utils.h"
#import "Host+CoreDataClass.h"

@interface TemporaryHost : NSObject

@property (atomic) State state;
@property (atomic) PairState pairState;
@property (atomic, nullable, retain) NSString * activeAddress;
@property (atomic, nullable, retain) NSString * currentGame;
@property (atomic) unsigned short httpsPort;
@property (atomic) BOOL isNvidiaServerSoftware;

@property (atomic, nullable, retain) NSData *serverCert;
@property (atomic, nullable, retain) NSString *address;
@property (atomic, nullable, retain) NSString *externalAddress;
@property (atomic, nullable, retain) NSString *localAddress;
@property (atomic, nullable, retain) NSString *ipv6Address;
@property (atomic, nullable, retain) NSString *mac;
@property (atomic)                   int serverCodecModeSupport;

// Apollo fork extension: the device streaming right now, nil when nobody streams
// or the host withholds it
@property (atomic, nullable, retain) NSString *activeStreamClient;
// True when the host sends the element at all. Apollo always does (empty when nobody
// streams); stock Sunshine never does, so a running app means somebody else is streaming.
@property (atomic) BOOL reportsActiveClient;

// Vibepollo power actions, from the paired /serverinfo. Transient: not stored in Core Data,
// so no migration. `powerActionVersion` stays 0 for hosts that send no version element,
// which is how a host without native sleep is told apart.
@property (atomic) int powerActionVersion;
@property (atomic) BOOL sleepSupported;
@property (atomic) BOOL sleepAllowed;

NS_ASSUME_NONNULL_BEGIN

@property (atomic, retain) NSString *name;
@property (atomic, retain) NSString *uuid;
@property (atomic, retain) NSSet *appList;

- (id) initFromHost:(Host*)host;

- (NSComparisonResult)compareName:(TemporaryHost *)other;

- (void) propagateChangesToParent:(Host*)host;

NS_ASSUME_NONNULL_END

@end
