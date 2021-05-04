// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <UserNotifications/UserNotifications.h>

#import "FLTFirebaseMessagingPlugin.h"

#import "Firebase/Firebase.h"

NSString *const kGCMMessageIDKey = @"gcm.message_id";

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@interface FLTFirebaseMessagingPlugin () <FIRMessagingDelegate>
@end
#endif

static FlutterError *getFlutterError(NSError *error) {
  if (error == nil) return nil;
  return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %ld", (long)error.code]
                             message:error.domain
                             details:error.localizedDescription];
}

static NSObject<FlutterPluginRegistrar> *_registrar;

@implementation FLTFirebaseMessagingPlugin {
  FlutterMethodChannel *_channel;
  NSDictionary *_launchNotification;
  BOOL _resumingFromBackground;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  _registrar = registrar;
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/firebase_messaging"
                                  binaryMessenger:[registrar messenger]];
  FLTFirebaseMessagingPlugin *instance =
      [[FLTFirebaseMessagingPlugin alloc] initWithChannel:channel];
  [registrar addApplicationDelegate:instance];
  [registrar addMethodCallDelegate:instance channel:channel];

  SEL sel = NSSelectorFromString(@"registerLibrary:withVersion:");
  if ([FIRApp respondsToSelector:sel]) {
    [FIRApp performSelector:sel withObject:LIBRARY_NAME withObject:LIBRARY_VERSION];
  }
}

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel {
  self = [super init];

  if (self) {
    _channel = channel;
    _resumingFromBackground = NO;
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  // NSString *method = call.method;
  
}

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0

// Received data message on iOS 10 devices while app is in the foreground.
// Only invoked if method swizzling is disabled and UNUserNotificationCenterDelegate has been
// registered in AppDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
    NS_AVAILABLE_IOS(10.0) {
  NSDictionary *userInfo = notification.request.content.userInfo;
  // Check to key to ensure we only handle messages from Firebase
  if (userInfo[kGCMMessageIDKey]) {
    [[FIRMessaging messaging] appDidReceiveMessage:userInfo];
    [_channel invokeMethod:@"onMessage" arguments:userInfo];
    completionHandler(UNNotificationPresentationOptionNone);
  }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler NS_AVAILABLE_IOS(10.0) {
  NSDictionary *userInfo = response.notification.request.content.userInfo;
  // Check to key to ensure we only handle messages from Firebase
  if (userInfo[kGCMMessageIDKey]) {
    [_channel invokeMethod:@"onResume" arguments:userInfo];
    completionHandler();
  }
}

#endif

- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo {
  if (_resumingFromBackground) {
    [_channel invokeMethod:@"onResume" arguments:userInfo];
  } else {
    [_channel invokeMethod:@"onMessage" arguments:userInfo];
  }
}

#pragma mark - AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  if (launchOptions != nil) {
    _launchNotification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
  }
  return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
  _resumingFromBackground = YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  _resumingFromBackground = NO;
  // Clears push notifications from the notification center, with the
  // side effect of resetting the badge count. We need to clear notifications
  // because otherwise the user could tap notifications in the notification
  // center while the app is in the foreground, and we wouldn't be able to
  // distinguish that case from the case where a message came in and the
  // user dismissed the notification center without tapping anything.
  // TODO(goderbauer): Revisit this behavior once we provide an API for managing
  // the badge number, or if we add support for running Dart in the background.
  // Setting badgeNumber to 0 is a no-op (= notifications will not be cleared)
  // if it is already 0,
  // therefore the next line is setting it to 1 first before clearing it again
  // to remove all
  // notifications.
  application.applicationIconBadgeNumber = 1;
  application.applicationIconBadgeNumber = 0;
}

- (BOOL)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
  [self didReceiveRemoteNotification:userInfo];
  completionHandler(UIBackgroundFetchResultNoData);
  return YES;
}

- (void)application:(UIApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {

}

// This will only be called for iOS < 10. For iOS >= 10, we make this call when we request
// permissions.
- (void)application:(UIApplication *)application
    didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
  NSDictionary *settingsDictionary = @{
    @"sound" : [NSNumber numberWithBool:notificationSettings.types & UIUserNotificationTypeSound],
    @"badge" : [NSNumber numberWithBool:notificationSettings.types & UIUserNotificationTypeBadge],
    @"alert" : [NSNumber numberWithBool:notificationSettings.types & UIUserNotificationTypeAlert],
    @"provisional" : [NSNumber numberWithBool:NO],
  };
  [_channel invokeMethod:@"onIosSettingsRegistered" arguments:settingsDictionary];
}


@end
