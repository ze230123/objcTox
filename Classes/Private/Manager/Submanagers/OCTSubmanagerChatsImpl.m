// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#import "OCTSubmanagerChatsImpl.h"
#import "OCTTox.h"
#import "OCTRealmManager.h"
#import "OCTMessageAbstract.h"
#import "OCTMessageText.h"
#import "OCTChat.h"
#import "OCTLogging.h"

@implementation OCTSubmanagerChatsImpl
@synthesize dataSource = _dataSource;

- (void)dealloc
{
    [self.dataSource.managerGetNotificationCenter removeObserver:self];
}

- (void)configure
{
    [self.dataSource.managerGetNotificationCenter addObserver:self
                                                     selector:@selector(friendConnectionStatusChangeNotification:)
                                                         name:kOCTFriendConnectionStatusChangeNotification
                                                       object:nil];
}

#pragma mark -  Public

- (OCTChat *)getOrCreateChatWithFriend:(OCTFriend *)friend
{
    return [[self.dataSource managerGetRealmManager] getOrCreateChatWithFriend:friend];
}

- (void)removeMessages:(NSArray<OCTMessageAbstract *> *)messages
{
    [[self.dataSource managerGetRealmManager] removeMessages:messages];
    [self.dataSource.managerGetNotificationCenter postNotificationName:kOCTScheduleFileTransferCleanupNotification object:nil];
}

- (void)removeAllMessagesInChat:(OCTChat *)chat removeChat:(BOOL)removeChat
{
    [[self.dataSource managerGetRealmManager] removeAllMessagesInChat:chat removeChat:removeChat];
    [self.dataSource.managerGetNotificationCenter postNotificationName:kOCTScheduleFileTransferCleanupNotification object:nil];
}

- (OCTMessageAbstract *)sendMessageToChat:(OCTChat *)chat
                                     text:(NSString *)text
                                     type:(OCTToxMessageType)type
                                    error:(NSError **)error
{
    NSParameterAssert(chat);
    NSParameterAssert(text);

    OCTTox *tox = [self.dataSource managerGetTox];
    OCTFriend *friend = [chat.friends firstObject];

    NSError *localError = nil;
    OCTToxMessageId messageId = [tox sendMessageWithFriendNumber:friend.friendNumber type:type message:text error:&localError];

    if (localError) {
        if (error) {
            *error = localError;
        }
        return nil;
    }

    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    return [realmManager addMessageWithText:text type:type chat:chat sender:nil messageId:messageId];
}

- (BOOL)setIsTyping:(BOOL)isTyping inChat:(OCTChat *)chat error:(NSError **)error
{
    NSParameterAssert(chat);

    OCTFriend *friend = [chat.friends firstObject];
    OCTTox *tox = [self.dataSource managerGetTox];

    return [tox setUserIsTyping:isTyping forFriendNumber:friend.friendNumber error:error];
}

#pragma mark -  NSNotification

- (void)friendConnectionStatusChangeNotification:(NSNotification *)notification
{
    OCTFriend *friend = notification.object;

    if (! friend) {
        OCTLogWarn(@"no friend received in notification %@, exiting", notification);
        return;
    }

    if (friend.isConnected) {
        [self resendUndeliveredMessagesToFriend:friend];
    }
}

#pragma mark -  Private

- (void)resendUndeliveredMessagesToFriend:(OCTFriend *)friend
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@"
                              @" AND senderUniqueIdentifier == nil"
                              @" AND messageText.isDelivered == NO",
                              chat.uniqueIdentifier];

    RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];
    OCTTox *tox = [self.dataSource managerGetTox];

    for (OCTMessageAbstract *message in results) {
        OCTLogInfo(@"Resending message to friend %@", friend);

        NSError *error;
        OCTToxMessageId messageId = [tox sendMessageWithFriendNumber:friend.friendNumber
                                                                type:message.messageText.type
                                                             message:message.messageText.text
                                                               error:&error];

        if (error) {
            OCTLogWarn(@"Cannot resend message to friend %@, error %@", friend, error);
            continue;
        }

        [realmManager updateObject:message withBlock:^(OCTMessageAbstract *theMessage) {
            theMessage.messageText.messageId = messageId;
        }];
    }
}

#pragma mark -  OCTToxDelegate

- (void)tox:(OCTTox *)tox friendMessage:(NSString *)message type:(OCTToxMessageType)type friendNumber:(OCTToxFriendNumber)friendNumber
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    OCTFriend *friend = [realmManager friendWithFriendNumber:friendNumber];
    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    [realmManager addMessageWithText:message type:type chat:chat sender:friend messageId:0];
}

- (void)tox:(OCTTox *)tox messageDelivered:(OCTToxMessageId)messageId friendNumber:(OCTToxFriendNumber)friendNumber
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    OCTFriend *friend = [realmManager friendWithFriendNumber:friendNumber];
    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@ AND messageText.messageId == %d",
                              chat.uniqueIdentifier, messageId];

    RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];

    OCTMessageAbstract *message = [results firstObject];

    if (! message) {
        return;
    }

    [realmManager updateObject:message withBlock:^(OCTMessageAbstract *theMessage) {
        theMessage.messageText.isDelivered = YES;
    }];
}

@end
