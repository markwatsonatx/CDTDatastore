//
//  TDPuller2.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Modifications for this distribution by Cloudant, Inc., Copyright (c) 2014 Cloudant, Inc.
//

#import "CDTActiveDocFetcherDelegate.h"
#import "TDReplicator.h"
#import "TD_Revision.h"
@class TDActiveDocChangeTracker, TDSequenceMap;

/** Replicator that pulls from a remote CouchDB. */
@interface TDActiveDocPuller : TDReplicator {
@private
    TDActiveDocChangeTracker* _changeTracker;
    BOOL _caughtUp;                      // Have I received all current _changes entries?
    TDSequenceMap* _pendingSequences;    // Received but not yet copied into local DB
    NSMutableArray* _revsToPull;         // Queue of TDPulledRevisions to download
    NSMutableArray* _deletedRevsToPull;  // Separate lower-priority of deleted TDPulledRevisions
    NSMutableArray* _bulkRevsToPull;     // TDPulledRevisions that can be fetched in bulk - 'all docs trick' for first rev
    NSMutableArray* _bulkGetRevs;        // <docid,revid> pairs to pull if the /_bulk_get endpoint is supported
    NSUInteger _httpConnectionCount;     // Number of active NSURLConnections
    TDBatcher* _downloadsToInsert;       // Queue of TDPulledRevisions, with bodies, to insert in DB
}

@property BOOL bulkGetSupported;

@end