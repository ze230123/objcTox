//
//  OCTDBManagerTests.m
//  objcTox
//
//  Created by Dmytro Vorobiov on 19.04.15.
//  Copyright (c) 2015 dvor. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>
#import <Realm/Realm.h>
#import <XCTest/XCTest.h>

#import "OCTDBManager.h"
#import "OCTDBFriendRequest.h"
#import "OCTDBChat.h"

@interface OCTDBManager()

@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) RLMRealm *realm;

@end

@interface OCTDBManagerTests : XCTestCase

@property (strong, nonatomic) OCTDBManager *manager;

@end

@implementation OCTDBManagerTests

- (NSString *)realmPath
{
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];

    return [directory stringByAppendingPathComponent:@"test.realm"];
}

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.

    self.manager = [[OCTDBManager alloc] initWithDatabasePath:[self realmPath]];
}

- (void)tearDown
{
    NSString *realmPath = [self realmPath];
    NSString *lockPath = [realmPath stringByAppendingString:@".lock"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:realmPath error:nil];
    [fileManager removeItemAtPath:lockPath error:nil];

    self.manager = nil;
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testInit
{
    XCTAssertNotNil(self.manager);
    XCTAssertNotNil(self.manager.queue);
    XCTAssertNotNil(self.manager.realm);
    XCTAssertEqualObjects(self.manager.realm.path, [self realmPath]);
}

- (void)testUpdateDBObjectWithBlock
{
    OCTDBFriendRequest *db = [OCTDBFriendRequest new];
    db.publicKey = @"key";
    db.message = @"message";

    [self.manager.realm beginWriteTransaction];
    [self.manager.realm addObject:db];
    [self.manager.realm commitWriteTransaction];

    [self.manager updateDBObjectInBlock:^{
        db.message = @"updated message";
    }];

    OCTDBFriendRequest *updated = [OCTDBFriendRequest objectInRealm:self.manager.realm forPrimaryKey:db.publicKey];

    XCTAssertEqualObjects(updated.message, @"updated message");
}

#pragma mark -  Friends

- (void)testAllFriendRequests
{
    OCTDBFriendRequest *db1 = [OCTDBFriendRequest new];
    db1.publicKey = @"key1";
    db1.message = @"message1";

    OCTDBFriendRequest *db2 = [OCTDBFriendRequest new];
    db2.publicKey = @"key2";
    db2.message = @"message2";

    [self.manager.realm beginWriteTransaction];
    [self.manager.realm addObject:db1];
    [self.manager.realm addObject:db2];
    [self.manager.realm commitWriteTransaction];

    RLMResults *results = [self.manager allFriendRequests];

    XCTAssertEqual(results.count, 2);

    XCTAssertEqualObjects(db1.publicKey, [results[0] publicKey]);
    XCTAssertEqualObjects(db1.message, [results[0] message]);
    XCTAssertEqualObjects(db2.publicKey, [results[1] publicKey]);
    XCTAssertEqualObjects(db2.message, [results[1] message]);
}

- (void)testAddFriendRequest
{
    OCTDBFriendRequest *request = [OCTDBFriendRequest new];
    request.publicKey = @"key";
    request.message = @"message";

    [self.manager addFriendRequest:request];

    OCTDBFriendRequest *db = [OCTDBFriendRequest objectInRealm:self.manager.realm forPrimaryKey:request.publicKey];

    XCTAssertNotNil(db);
    XCTAssertEqualObjects(request.publicKey, db.publicKey);
    XCTAssertEqualObjects(request.message, db.message);
}

- (void)testRemoveFriendRequestWithPublicKey
{
    OCTDBFriendRequest *request = [OCTDBFriendRequest new];
    request.publicKey = @"key";
    request.message = @"message";

    [self.manager.realm beginWriteTransaction];
    [self.manager.realm addObject:request];
    [self.manager.realm commitWriteTransaction];

    [self.manager removeFriendRequestWithPublicKey:@"key"];

    XCTAssertThrowsSpecific(
            [OCTDBFriendRequest objectInRealm:self.manager.realm forPrimaryKey:request.publicKey],
            NSException);
}

- (void)testAllChats
{
    OCTDBChat *db1 = [OCTDBChat new];
    db1.enteredText = @"";
    db1.lastReadDateInterval = 5;

    OCTDBChat *db2 = [OCTDBChat new];
    db2.enteredText = @"";
    db2.lastReadDateInterval = 10;

    [self.manager.realm beginWriteTransaction];
    [self.manager.realm addObject:db1];
    [self.manager.realm addObject:db2];
    [self.manager.realm commitWriteTransaction];

    RLMResults *results = [self.manager allChats];

    XCTAssertEqual(results.count, 2);

    XCTAssertEqualObjects(db1.enteredText, [results[0] enteredText]);
    XCTAssertEqual(db1.lastReadDateInterval, [results[0] lastReadDateInterval]);
    XCTAssertEqualObjects(db2.enteredText, [results[1] enteredText]);
    XCTAssertEqual(db2.lastReadDateInterval, [results[1] lastReadDateInterval]);
}

@end
