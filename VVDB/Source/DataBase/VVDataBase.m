//
// Created by Tank on 2019-07-08.
// Copyright (c) 2019 Tank. All rights reserved.
//

#import "VVDataBase.h"

#import <FMDB/FMDatabaseQueue.h>
#import <sqlite3.h>

#import "VVModelInterface.h"
#import "VVRelationshipModel.h"
#import "VVDBRuntime.h"
#import "VVDBRuntimeProperty.h"
#import "VVDBSQLiteConditionModel.h"

@interface VVMigration (Protected)

- (BOOL)migrate:(FMDatabase *)db error:(NSError **)error;

@end

@interface VVReferenceMapper (Protected)

- (NSNumber *)existsObject:(NSObject *)object db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)max:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)min:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)avg:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)total:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)sum:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)count:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (NSNumber *)referencedCount:(NSObject *)object db:(FMDatabase *)db error:(NSError **)error;

- (NSMutableArray *)fetchReferencingObjectsWithToObject:(NSObject *)object db:(FMDatabase *)db error:(NSError **)error;

- (NSArray *)refreshObject:(NSObject *)object db:(FMDatabase *)db error:(NSError **)error;

- (NSMutableArray *)fetchObjects:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (BOOL)saveObjects:(NSArray *)objects db:(FMDatabase *)db error:(NSError **)error;

- (BOOL)deleteObjects:(NSArray *)objects db:(FMDatabase *)db error:(NSError **)error;

- (BOOL)deleteObjects:(Class)clazz condition:(VVDBConditionModel *)condition db:(FMDatabase *)db error:(NSError **)error;

- (VVDBRuntime *)runtime:(Class)clazz;

- (BOOL)registerRuntime:(VVDBRuntime *)runtime db:(FMDatabase *)db error:(NSError **)error;

- (BOOL)unRegisterRuntime:(VVDBRuntime *)runtime db:(FMDatabase *)db error:(NSError **)error;

- (void)setUnRegistedAllRuntimeFlag;

- (void)setRegistedRuntimeFlag:(VVDBRuntime *)runtime;

- (void)setUnRegistedRuntimeFlag:(VVDBRuntime *)runtime;
@end


@interface VVDataBase ()

@property(nonatomic, weak) VVDataBase *weakSelf;
@property(nonatomic, strong) FMDatabaseQueue *dbQueue;
@property(nonatomic, strong) FMDatabase *db;
@property(nonatomic, assign) BOOL rollback;

@end

@implementation VVDataBase

#pragma mark constractor method

+ (instancetype)openWithPath:(NSString *)path error:(NSError **)error {
    if (path && ![path isEqualToString:@""]) {
        if ([path isEqualToString:[path lastPathComponent]]) {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
            NSString *dir = [paths firstObject];
            path = [dir stringByAppendingPathComponent:path];
#ifdef DEBUG
            NSLog(@"database path = %@", path);
#endif
        }
    }

    FMDatabaseQueue *dbQueue = [self dbQueueWithPath:path];
    if (!dbQueue) {
        return nil;
    }

    VVDataBase *os = [[self alloc] init];
    os.dbQueue = dbQueue;
    os.db = nil;
    os.weakSelf = os;

    NSError *err = nil;
    [os registerClass:[VVRelationshipModel class] error:&err];
    if (err) {
        *error = err;
        return nil;
    }
    [os registerClass:[VVDBRuntime class] error:&err];
    if (err) {
        *error = err;
        return nil;
    }
    [os registerClass:[VVDBRuntimeProperty class] error:&err];
    if (err) {
        *error = err;
        return nil;
    }
    return os;
}

+ (FMDatabaseQueue *)dbQueueWithPath:(NSString *)path {
    FMDatabaseQueue *dbQueue = [FMDatabaseQueue databaseQueueWithPath:path flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FILEPROTECTION_NONE];
    return dbQueue;
}

#pragma mark inTransaction

- (void)inTransactionWithBlock:(void (^)(FMDatabase *db, BOOL *rollback))block {
    @synchronized (self) {
        if (self.db) {
            if (block) {
                block(self.db, &_rollback);
            }
        } else {
            [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
                [_weakSelf transactionDidBegin:db];
                _weakSelf.db = db;
                [db setShouldCacheStatements:YES];
                block(db, rollback);
                if (*rollback) {
                    [_weakSelf setUnRegistedAllRuntimeFlag];
                }
            }];
            [self transactionDidEnd:self.db];
            self.db = nil;
        }
    }
}

- (void)transactionDidBegin:(FMDatabase *)db {
}

- (void)transactionDidEnd:(FMDatabase *)db {
}

#pragma mark transaction

- (void)inTransaction:(void (^)(VVDataBase *dataBase, BOOL *rollback))block {
    __weak VVDataBase *weakSelf = self;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        block(weakSelf, rollback);
    }];
}

#pragma mark exists, count, min, max methods

- (NSNumber *)existsObject:(NSObject *)object error:(NSError **)error {
    __block NSError *err = nil;
    __block NSNumber *exists = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        exists = [_weakSelf existsObject:object db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return exists;
}

- (NSNumber *)count:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block NSNumber *value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf count:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSNumber *)max:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block id value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf max:columnName class:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSNumber *)min:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block id value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf min:columnName class:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSNumber *)total:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block id value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf total:columnName class:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSNumber *)sum:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block id value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf sum:columnName class:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSNumber *)avg:(NSString *)columnName class:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block id value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf avg:columnName class:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}


#pragma mark fetch count methods

- (NSNumber *)referencedCount:(NSObject *)object error:(NSError **)error {
    __block NSError *err = nil;
    __block NSNumber *value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf referencedCount:object db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSMutableArray *)fetchReferencingObjectsTo:(NSObject *)object error:(NSError **)error {
    __block NSError *err = nil;
    __block NSMutableArray *list = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        list = [_weakSelf fetchReferencingObjectsWithToObject:object db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return list;
}


#pragma mark fetch methods

- (NSMutableArray *)fetchObjects:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block NSMutableArray *value = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        value = [_weakSelf fetchObjects:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return value;
}

- (NSMutableArray *)fetchObjects:(Class)clazz where:(NSString *)where parameters:(NSArray *)parameters orderBy:(NSString *)orderBy error:(NSError **)error {
    VVDBConditionModel *condition = [VVDBConditionModel condition];
    condition.sqlite.where = where;
    condition.sqlite.parameters = parameters;
    condition.sqlite.orderBy = orderBy;
    return [self fetchObjects:clazz condition:condition error:error];
}

- (NSMutableArray *)fetchObjects:(Class)clazz where:(NSString *)where parameters:(NSArray *)parameters orderBy:(NSString *)orderBy offset:(NSNumber *)offset limit:(NSNumber *)limit error:(NSError **)error {
    VVDBConditionModel *condition = [VVDBConditionModel condition];
    condition.sqlite.where = where;
    condition.sqlite.parameters = parameters;
    condition.sqlite.orderBy = orderBy;
    condition.sqlite.offset = offset;
    condition.sqlite.limit = limit;
    return [self fetchObjects:clazz condition:condition error:error];
}

- (id)refreshObject:(NSObject *)object error:(NSError **)error {
    __block NSError *err = nil;
    __block NSObject *latestObject = nil;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        latestObject = [_weakSelf refreshObject:object db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return latestObject;
}


#pragma mark save methods

- (BOOL)saveObjects:(NSArray *)objects error:(NSError **)error {
    if (![[objects class] isSubclassOfClass:[NSArray class]]) {
        return NO;
    }
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        ret = [_weakSelf saveObjects:objects db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
        return;
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

- (BOOL)saveObject:(NSObject *)object error:(NSError **)error {
    if (!object) {
        return NO;
    }
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        ret = [_weakSelf saveObjects:@[object] db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

#pragma mark delete methods

- (BOOL)deleteObjects:(Class)clazz condition:(VVDBConditionModel *)condition error:(NSError **)error {
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        [db setShouldCacheStatements:YES];
        ret = [_weakSelf deleteObjects:clazz condition:condition db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
        return;
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

- (BOOL)deleteObjects:(Class)clazz where:(NSString *)where parameters:(NSArray *)parameters error:(NSError **)error {
    VVDBConditionModel *condition = [VVDBConditionModel condition];
    condition.sqlite.where = where;
    condition.sqlite.parameters = parameters;
    return [self deleteObjects:clazz condition:condition error:error];
}

- (BOOL)deleteObject:(NSObject *)object error:(NSError **)error {
    if (!object) {
        return NO;
    }
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        ret = [_weakSelf deleteObjects:@[object] db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
        return;
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

- (BOOL)deleteObjects:(NSArray *)objects error:(NSError **)error {
    if (![[objects class] isSubclassOfClass:[NSArray class]]) {
        return NO;
    }
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        ret = [_weakSelf deleteObjects:objects db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

#pragma register methods

- (BOOL)registerClass:(Class)clazz error:(NSError **)error {
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        VVDBRuntime *runtime = [self runtime:clazz];
        ret = [_weakSelf registerRuntime:runtime db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
        [self setRegistedRuntimeFlag:runtime];
        return;
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

- (BOOL)unRegisterClass:(Class)clazz error:(NSError **)error {
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        VVDBRuntime *runtime = [self runtime:clazz];
        ret = [_weakSelf unRegisterRuntime:runtime db:db error:&err];
        if ([db hadError]) {
            err = [db lastError];
        }
        if (err) {
            *rollback = YES;
        }
        [self setUnRegistedRuntimeFlag:runtime];
        return;
    }];
    if (error) {
        *error = err;
    }
    return ret;
}

- (BOOL)migrate:(NSError **)error {
    __block NSError *err = nil;
    __block BOOL ret = NO;
    [self inTransactionWithBlock:^(FMDatabase *db, BOOL *rollback) {
        ret = [self migrate:db error:&err];
        return;
    }];
    if (!ret) {
        *error = err;
    }
    return ret;
}

- (void)close {
    [self.dbQueue close];
    self.dbQueue = nil;
    self.db = nil;
}


@end
