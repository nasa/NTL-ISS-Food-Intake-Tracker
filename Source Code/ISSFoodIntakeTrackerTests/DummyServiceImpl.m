// Copyright (c) 2013 TopCoder. All rights reserved.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//
//  DummyServiceImpl.m
//  ISSFoodIntakeTracker
//
//  Created by Xiaoyang Du on 2013-07-13.
//

#import "DummyServiceImpl.h"

@implementation DummyServiceImpl

@synthesize lockAcquired;

-(void)acquireLock:(User *)user error:(NSError **)error {
    lockAcquired = YES;
}

-(void) releaseLock:(User*)user error:(NSError**)error {
    lockAcquired = NO;
}

-(void) sendLockHeartbeat:(User*)user error:(NSError**)error {
    
}

@end
