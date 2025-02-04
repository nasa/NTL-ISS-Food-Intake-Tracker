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
//  AppDelegate.m
//  FoodIntakeTracker
//
//  Created by lofzcx 06/12/2013
//
//  Updated by pvmagacho on 05/07/2014
//  F2Finish - NASA iPad App Updates
//
//  Updated by pvmagacho on 05/14/2014
//  F2Finish - NASA iPad App Updates - Round 3
//

#import <HockeySDK/HockeySDK.h>
#import <BugfenderSDK/BugfenderSDK.h>

#import "AppDelegate.h"
#import "UserServiceImpl.h"
#import "FoodProductServiceImpl.h"
#import "FoodConsumptionRecordServiceImpl.h"
#import "SynchronizationServiceImpl.h"
#import "DataUpdateServiceImpl.h"
#import "DataHelper.h"
#import "DBHelper.h"
#import "Settings.h"
#import "Helper.h"
#import "LoggingHelper.h"

#import "WebserviceCoreData.h"

typedef NS_ENUM(NSInteger, SyncStatus) {
    SyncStatusNone,
    
    SyncStatusStarted,
    SyncStatusFinished,
    SyncStatusError
} NS_ENUM_AVAILABLE_IOS(7_0);

/**
 * the application delegate
 *
 * @author lofzcx
 * @version 1.0
 */
@implementation AppDelegate {
    /*! Indicates whether the data loading is done. */
    BOOL loadingFinished;
    /*! Indicates if there was a server change. */
    BOOL changed;
    /*! Lock for change */
    NSLock *lock;
    /*! Synchronization status */
    SyncStatus status;
    
    UIBackgroundTaskIdentifier backgroundTask;

    NSInteger dataUpdateCount;
}

@synthesize tabBarViewController;

- (TouchWindow *)window
{
    static TouchWindow *customWindow = nil;
    if (!customWindow) customWindow = [[TouchWindow alloc] init];
    
    CGFloat systemVersion = [[[UIDevice currentDevice] systemVersion] floatValue];
    if(systemVersion < 7) {
        customWindow.frame = [[UIScreen mainScreen] bounds];
    }
    else {
        CGRect bounds = [[UIScreen mainScreen] bounds];
        CGFloat diff = 20;
        customWindow.frame = CGRectMake(bounds.origin.x, bounds.origin.y + diff, bounds.size.width, bounds.size.height - diff);
        customWindow.bounds = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height - diff);
        customWindow.autoresizingMask = UIViewAutoresizingNone;
    }
    
    return customWindow;
}

/**
 * following delegate methods is application delegate, overwrite to define action for application loaded, ended,
 * entering background, become active. For this assembly just leave these empty.
 *
 */

/*!
 * This method tells the delegate that the launch process is almost done and the app is almost ready to run.
 * @param application the delegating application object
 * @param launchOptions the launch options
 * @return NO if the application cannot handle the URL resource, otherwise return YES.
 The return value is ignored if the application is launched as a result of a remote notification.
 */
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    dataUpdateCount = 0;
    status = SyncStatusNone;
    dataSyncUpdateQ = dispatch_queue_create("Data Sync Update", NULL);
   
    lock = [[NSLock alloc] init];
    [lock setName:@"UpdateLock"];

    //http://stackoverflow.com/questions/17678881/how-to-change-status-bar-text-color-in-ios-7
    [application setStatusBarStyle:UIStatusBarStyleLightContent];
    
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    if (![standardUserDefaults objectForKey:@"address_preference"] ||
        ![standardUserDefaults objectForKey:@"user_preference"] ||
        ![standardUserDefaults objectForKey:@"password_preference"] ||
        ![standardUserDefaults objectForKey:@"port_preference"]) {
        [self registerDefaultsFromSettingsBundle];
    }
    
    NSString *uuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"UUID"];
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:uuid forKey:@"UUID"];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSettingsChange:)
                                                 name:NSUserDefaultsDidChangeNotification object:nil];

    // Load configurations and create services
    NSString *configBundle = [[NSBundle mainBundle] pathForResource:@"Configuration" ofType:@"plist"];
    if (configBundle) {
        NSDictionary *dict = [[NSUserDefaults standardUserDefaults] objectForKey:@"CurrentConfiguration"];
        if (!dict) {
            self.configuration = [[NSDictionary dictionaryWithContentsOfFile:configBundle] mutableCopy];
            [self modifyCurrentConfiguration];
        } else {
            self.configuration = [dict mutableCopy];
            if ([self isServerChanged]) {
                // samba sever configuration has changed
                [self modifyCurrentConfiguration];
                [self doServerChange];
            }
        }


        if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"enable_remote_log"] boolValue]) {
            NSString *hockeyAppKey = [self.configuration valueForKey:@"HockeyAppKey"];
            NSString *bugfenderKey = [self.configuration valueForKey:@"BugfenderKey"];

            [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:hockeyAppKey];
            [[BITHockeyManager sharedHockeyManager] startManager];
            [[BITHockeyManager sharedHockeyManager].authenticator authenticateInstallation];

            [Bugfender activateLogger:bugfenderKey];
        }

        self.shouldAutoLogout = NO;
        loadingFinished = NO;
        
        self.userService = [[UserServiceImpl alloc] initWithConfiguration:self.configuration];
        self.foodProductService = [[FoodProductServiceImpl alloc] init];
        self.foodConsumptionRecordService = [[FoodConsumptionRecordServiceImpl alloc] initWithConfiguration:self.configuration];
        self.synchronizationService = [[SynchronizationServiceImpl alloc] initWithConfiguration:self.configuration];
        self.dataUpdateService = [[DataUpdateServiceImpl alloc] initWithConfiguration:self.configuration];
        
        NSDictionary *localConf = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:configBundle]];
        self.additionalFilesDirectory = [localConf valueForKey:@"LocalFileSystemDirectory"];
        self.helpData = [localConf objectForKey:@"HelpData"];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(doSyncUpdate:) name:@"DataSyncUpdate"
                                                   object:nil];

        if (!changed) {
            if ([standardUserDefaults boolForKey:@"PasswordConfirm"]) {
                [self initialLoad];
            }
        }

        if (loadingFinished) {
            [self removeUserLock];
        }

        return YES;
    } else {
        return NO;
    }
    
    backgroundTask = UIBackgroundTaskInvalid;
    
    // Override point for customization after application launch.
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of
    // temporary interruptions (such as an incoming phone call or SMS message) or
    // when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates.
    // Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application
    // state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of
    // applicationWillTerminate: when the user quits.
    
    if (loadingFinished && status == SyncStatusStarted && backgroundTask == UIBackgroundTaskInvalid) {
        backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^ {
            [application endBackgroundTask:backgroundTask];
            backgroundTask = UIBackgroundTaskInvalid;
        }];
        
        // Start the long-running task and return immediately.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            // Do the work associated with the task, preferably in chunks.
            while (status == SyncStatusStarted) {
                [NSThread sleepForTimeInterval:1];
                [LoggingHelper logDebug:@"applicationDidEnterBackground"
                                message:[NSString stringWithFormat:@"Waiting for synchronization: %f",
                                         application.backgroundTimeRemaining]];
            }
            
            [application endBackgroundTask:backgroundTask];
            backgroundTask = UIBackgroundTaskInvalid;
        });
    }

    if (self.shouldAutoLogout) {
        [self.tabBarViewController logout];
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state;
    // here you can undo many of the changes made on entering the background.
    if (status == SyncStatusFinished) {
        [self doSyncUpdate:nil];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive.
    // If the application was previously in the background, optionally refresh the user interface.
    if (!loadingFinished) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"PasswordConfirm"]) {
            UIAlertView *alertview = [[UIAlertView alloc] initWithTitle:@"Confirmation"
                                                                message:@"Please confirm/change password"
                                                               delegate:self
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            alertview.alertViewStyle = UIAlertViewStylePlainTextInput;
            [alertview textFieldAtIndex:0].delegate = self;
            [[alertview textFieldAtIndex:0] setText:[[NSUserDefaults standardUserDefaults] objectForKey:@"password_preference"]];
            [alertview show];
        }
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate.
    // See also applicationDidEnterBackground:.
}

+ (AppDelegate *) shareDelegate {
    return (AppDelegate *)[[UIApplication sharedApplication] delegate];
}

/*!
 * This method will do data sync/update.
 */
- (void) doSyncUpdate:(NSNotification *) notif {
    // Skip the sync/update if the initial load is still in progress.
    if (loadingFinished) {
        [self doSyncUpdateWithBlock:^(BOOL result) {
            if (dataUpdateCount <= 0) {
                NSDictionary *loadingEndParam = @{@"success": [NSNumber numberWithBool:result]};
                [[NSNotificationCenter defaultCenter] postNotificationName:InitialLoadingEndEvent
                                                                    object:loadingEndParam];
            }
        }];
    }
}

/*!
 * This method will do data sync/update.
 @param block code to be executed when synchronization has finished
 */
- (void) doSyncUpdateWithBlock:(void (^) (BOOL) ) block {
    // new call to sync update
    dataUpdateCount++;

    dispatch_async(dataSyncUpdateQ, ^{
        @autoreleasepool {
            if (!loadingFinished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    dataUpdateCount--;
                    block(NO);
                });
                
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:InitialLoadingBeginEvent object:nil];
            });
            
            status = SyncStatusStarted;

            NSError *error = nil;

            //[LoggingHelper logDebug:@"doSyncUpdateWithBlock"
            //                message:[NSString stringWithFormat:@"Start sync at   : %@", [NSDate date]]];

            BOOL result = [self.synchronizationService synchronize:&error];

            if (error.code == UserLockErrorCode ||
                error.code == UserRemovedErrorCode) {
                status = SyncStatusFinished;
                dataUpdateCount--;
                [LoggingHelper logDebug:@"doSyncUpdateWithBlock"
                                message:[NSString stringWithFormat:@"Sync interrupted at: %@", [NSDate date]]];
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                dataUpdateCount--;
                block(result);
            });

            status = SyncStatusFinished;

            [LoggingHelper logDebug:@"doSyncUpdateWithBlock"
                            message:[NSString stringWithFormat:@"Finished sync at: %@", [NSDate date]]];

            if (backgroundTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
                backgroundTask = UIBackgroundTaskInvalid;
            }
        }
    });
}


#pragma mark - Test Code

// Check if the app is started for the first time. If so, do some initializations.
- (void) initialLoad {
    status = SyncStatusStarted;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"HasLaunchedOnce"]) {
        loadingFinished = YES;
        /*NSDictionary *loadingEndParam = @{@"success": [NSNumber numberWithBool:YES]};
        [[NSNotificationCenter defaultCenter] postNotificationName:InitialLoadingEndEvent
                                                            object:loadingEndParam];*/
        
        [[NSNotificationCenter defaultCenter] postNotificationName:InitialLoadingBeginEvent object:nil];
        
        status = SyncStatusFinished;
        
        return;
    }
    
    // reset last sync time if it exists - reload everything
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LastSynchronizedTime"];
    
    loadingFinished = NO;
    __block BOOL syncSuccessful = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (changed) {
            [[NSNotificationCenter defaultCenter] postNotificationName:LoadingNewBeginEvent object:nil];
        } else {
            [DBHelper resetPersistentStore];
            [[NSNotificationCenter defaultCenter] postNotificationName:InitialLoadingBeginEvent object:nil];
        }
    });
    
    // dispatch_queue_t initialLoadQ = dispatch_queue_create("InitialLoad", NULL);
    dispatch_async(dataSyncUpdateQ, ^{
        @autoreleasepool {
            [LoggingHelper logDebug:@"initialLoad"
                            message:[NSString stringWithFormat:@"Initial load at: %@", [NSDate date]]];
            
            [lock lock];
            @try {
                NSError *error = nil;
                syncSuccessful = [self.dataUpdateService update:&error force:YES];

                if (error) {
                    [LoggingHelper logError:@"initialLoad" error:error];
                }

                syncSuccessful &= [[WebserviceCoreData instance] registerDevice];
                if (syncSuccessful) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasLaunchedOnce"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                }
            }
            @catch (NSException *exception) {
                syncSuccessful = NO;
                [LoggingHelper logException:@"initialLoad" error:exception];
            }
            
            if ([self.dataUpdateService cancelUpdate]) {
                [self.dataUpdateService setCancelUpdate:NO];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    loadingFinished = syncSuccessful;
                    NSDictionary *loadingEndParam = @{@"success": [NSNumber numberWithBool:syncSuccessful]};
                    [[NSNotificationCenter defaultCenter] postNotificationName:InitialLoadingEndEvent
                                                                            object:loadingEndParam];
                    
                    status = syncSuccessful ? SyncStatusFinished : SyncStatusError;
                });
            }
            [lock unlock];
        }
    });
    // dispatch_release(initialLoadQ);
}

#pragma mark - NSUserDefaults

- (void)registerDefaultsFromSettingsBundle {
    // this function writes default settings as settings
    NSString *settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    if(!settingsBundle) {
        [LoggingHelper logDebug:@"registerDefaultsFromSettingsBundle" message:@"Could not find Settings.bundle"];
        return;
    }
    
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray *preferences = [settings objectForKey:@"PreferenceSpecifiers"];
    
    NSMutableDictionary *defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];
    for(NSDictionary *prefSpecification in preferences) {
        NSString *key = [prefSpecification objectForKey:@"Key"];
        if(key) {
            [defaultsToRegister setObject:[prefSpecification objectForKey:@"DefaultValue"] forKey:key];
        }
    }
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsToRegister];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Configuration change methods

/*!
 * Handle change in ISS Fit settings.
 */
- (void)handleSettingsChange:(NSNotification *) notif {
    if (changed) {
        return;
    }
    
    if ([self isServerChanged]) {
        [self doServerChange];
    }
}

/*!
 * Reset stored data in application and load data from new samba server.
 */
- (void)resetData {
    // reset stored data
    [LoggingHelper logDebug:@"resetData" message:@"Resetting data."];

    [lock lock];
    [DBHelper resetPersistentStore];
    [lock unlock];

    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HasLaunchedOnce"];

    // change current configuration
    [self modifyCurrentConfiguration];
    
    self.userService = [[UserServiceImpl alloc] initWithConfiguration:self.configuration];
    self.foodProductService = [[FoodProductServiceImpl alloc] init];
    self.foodConsumptionRecordService = [[FoodConsumptionRecordServiceImpl alloc] initWithConfiguration:self.configuration];
    self.synchronizationService = [[SynchronizationServiceImpl alloc] initWithConfiguration:self.configuration];
    self.dataUpdateService = [[DataUpdateServiceImpl alloc] initWithConfiguration:self.configuration];
    
    // load data from new server
    [self initialLoad];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        changed = NO;
    });
}

/*!
 * Perform samba server change
 */
- (void)doServerChange {
    changed = YES;
    /*if ([[NSUserDefaults standardUserDefaults] boolForKey:@"HasLaunchedOnce"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[UIAlertView alloc] initWithTitle:@"Confirmation"
                                        message:@"Are you sure you want to change server"
                                       delegate:self
                              cancelButtonTitle:@"NO"
                              otherButtonTitles:@"YES", nil] show];
        });
    } else {*/
    [LoggingHelper logDebug:@"doServerChange" message:@"Settings changed."];

    [self.tabBarViewController logout];

    [self performSelectorInBackground:@selector(resetData) withObject:nil];
    //}
}

/*!
 * Indicates if the samba server has changed.
 * @return YES if samba server has changed, NO otherwise.
 */
- (BOOL) isServerChanged {
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    if (![self.configuration[@"SharedFileServerPath"] isEqualToString:[standardUserDefaults objectForKey:@"address_preference"]] ||
        ![self.configuration[@"SharedFileServerUsername"] isEqualToString:[standardUserDefaults objectForKey:@"user_preference"]] ||
        ![self.configuration[@"SharedFileServerPassword"] isEqualToString:[standardUserDefaults objectForKey:@"password_preference"]] ||
        ![self.configuration[@"SharedFileServerPort"] isEqualToString:[standardUserDefaults objectForKey:@"port_preference"]]) {
        return YES;
    }
    
    return NO;
}

/*!
 * Change current local configuration.
 */
- (void)modifyCurrentConfiguration {
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
    
    [self.configuration setObject:[standardUserDefaults objectForKey:@"address_preference"] forKey:@"SharedFileServerPath"];
    [self.configuration setObject:[standardUserDefaults objectForKey:@"user_preference"] forKey:@"SharedFileServerUsername"];
    [self.configuration setObject:[standardUserDefaults objectForKey:@"password_preference"] forKey:@"SharedFileServerPassword"];
    [self.configuration setObject:[standardUserDefaults objectForKey:@"port_preference"] forKey:@"SharedFileServerPort"];
    
    [[NSUserDefaults standardUserDefaults] setObject:self.configuration forKey:@"CurrentConfiguration"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - UIAlertViewDelegate methods

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
    [standardUserDefaults setObject:@YES forKey:@"PasswordConfirm"];
    [standardUserDefaults setObject:[alertView textFieldAtIndex:0].text forKey:@"password_preference"];
    [standardUserDefaults synchronize];

    [self doServerChange];
}

#pragma mark - User locks

/*!
 @discussion Remove user lock.
 */
- (void)removeUserLock {
    dispatch_async(dataSyncUpdateQ, ^{
        [[WebserviceCoreData instance] removeUserLock];
    });
}

/*!
 @discussion Check if user lock exists.
 * @param user the user to check.
 * @return true if lock was acquired or if user is already locked for this device, false otherwise.
 */
- (BOOL)checkLock:(User *)user {
    // check if current user has been lock by another device
    NSString *deviceUuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"DEVICE_UUID"];

    if (!user.id) {
        return YES;
    }

    [LoggingHelper logDebug:@"checkLock"
                    message:[NSString stringWithFormat:@"Checking lock for user %@", user.fullName]];

    NSArray *userLocks = [[WebserviceCoreData instance] fetchUserLocks];
    if (userLocks) {
        for (NSDictionary *dict in userLocks) {
            NSString *uid = [dict objectForKey:@"userId"];
            NSString *deviceId = [dict objectForKey:@"deviceId"];
            if ([uid isEqualToString:user.id] && [deviceId isEqualToString:deviceUuid]) {
                return YES;
            }
        }
    }

    [LoggingHelper logDebug:@"checkLock"
                    message:[NSString stringWithFormat:@"Failed to find lock for user %@ (%@) in %@",
                             user.fullName, user.id, userLocks]];

    return NO;
}

/*!
 @discussion Try to acquire a user lock.
 * @param user the user to set new lock.
 * @return true if lock was acquired or if user is already locked for this device, false otherwise.
 */
- (NSInteger)acquireLock:(User *)user {
    // check if current user has been lock by another device
    NSString *deviceUuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"DEVICE_UUID"];
    [LoggingHelper logDebug:@"acquireLock"
                    message:[NSString stringWithFormat:@"Acquiring lock for user %@", [user fullName]]];

    __block NSInteger result;
    __block NSString *userId = user.id ? [NSString stringWithString:user.id] : nil;
    dispatch_sync(dataSyncUpdateQ, ^{
        WebserviceCoreData *instance = [WebserviceCoreData instance];
        BOOL connect = [instance connect];

        if (!connect) {
            result = 1;
            return;
        }

        if (!userId) {
            result = -2;
            return;
        }

        NSArray *userLocks = [instance fetchUserLocks];
        if (userLocks) {
            for (NSDictionary *dict in userLocks) {
                NSString *uid = [dict objectForKey:@"userId"];
                NSString *deviceId = [dict objectForKey:@"deviceId"];
                if ([uid isEqualToString:userId]) {
                    result = [deviceId isEqualToString:deviceUuid] ? 1 : 0;
                    return;
                }
            }
        }

        connect = [instance connect];
        result = connect ? [instance insertUserLock:userId] : 1;
    });

    return result;
}

@end
