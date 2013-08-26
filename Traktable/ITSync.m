//
//  ITSync.m
//  Traktable
//
//  Created by Johan Kuijt on 26-08-13.
//  Copyright (c) 2013 Mustacherious. All rights reserved.
//

#import "ITSync.h"
#import "ITApi.h"
#import "ITDb.h"
#import "ITMoviePoster.h"
#import "ITTVShowPoster.h"
#import "ITConstants.h"

@interface ITSync()

@property dispatch_queue_t queue;
@property BOOL extended;

@end

@implementation ITSync

- (id)init {
    
    self = [super init];
	if (self) {
        _queue = dispatch_queue_create("traktable.sync.queue", NULL);
        _extended = NO;
    }
    
    return self;
}

- (void)syncTrakt {
    
    /** Sync movies **/
    [self sync:iTunesEVdKMovie extended:self.extended];
    
    /** Sync series **/
    [self sync:iTunesEVdKTVShow extended:self.extended];
}

- (void)sync:(iTunesEVdK)type extended:(BOOL)extended {
    
    ITApi *api = [ITApi new];
    ITDb *db = [ITDb new];
    
    NSArray *items = [api watchedSync:type extended:[NSString stringWithFormat:@"%d",extended]];
    
    for(NSDictionary *item in items) {
        
        NSDictionary *argsDict;
        NSString *table;
        
        if(type == iTunesEVdKMovie) {
            
            argsDict = [self getMovieParameters:item extended:extended];
            table = @"movies";
            
            if([db executeAndGetOneResult:@"SELECT overview FROM movies WHERE tmdb_id = :id" arguments:[NSArray arrayWithObject:[item objectForKey:@"tmdb_id"]]] != nil)
                continue;
            
        } else if(type == iTunesEVdKTVShow) {
            
            argsDict = [self getTVShowParameters:item extended:extended];
            table = @"tvshows";
            
            if([db executeAndGetOneResult:@"SELECT overview FROM tvshows WHERE tvdb_id = :id" arguments:[NSArray arrayWithObject:[item objectForKey:@"tvdb_id"]]] != nil)
                continue;
        }
        
        [db executeUpdateUsingQueue:[db getInsertFromDictionary:argsDict forTable:table] arguments:argsDict];
        
        NSLog(@"%@",[db lastErrorMessage]);
        
        NSNumber *lastId = [db lastInsertRowId];
        
        if([lastId intValue] == 0)
            continue;
        
        dispatch_async(self.queue,
           ^{
               if(type == iTunesEVdKMovie) {
                   [self getMoviePoster:lastId poster:[argsDict objectForKey:@"poster"]];
               } else if(type == iTunesEVdKTVShow) {
                   [self getTVShowPoster:lastId poster:[argsDict objectForKey:@"poster"]];
               }
           });
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kITHistoryNeedsUpdateNotification object:nil];
}

- (NSDictionary *)getMovieParameters:(NSDictionary *)movie extended:(BOOL)extended {
    
    NSString *posterUrl = [[movie objectForKey:@"images"] objectForKey:@"poster"];
    NSString *genres = [[movie objectForKey:@"genres"] componentsJoinedByString:@","];
    NSDictionary *argsDict;
    
    if(extended) {
        
        argsDict = [NSDictionary dictionaryWithObjectsAndKeys:[movie objectForKey:@"tmdb_id"], @"tmdb_id", [movie objectForKey:@"imdb_id"],@"imdb_id",[movie objectForKey:@"year"],@"year", posterUrl,@"poster",[movie objectForKey:@"plays"],@"traktPlays",[movie objectForKey:@"released"],@"released",[movie objectForKey:@"runtime"],@"runtime",[movie objectForKey:@"title"],@"title",[movie objectForKey:@"overview"],@"overview",[movie objectForKey:@"tagline"],@"tagline",[movie objectForKey:@"url"],@"traktUrl",[movie objectForKey:@"trailer"],@"trailer",genres,@"genres", nil];
        
    } else {
        
        argsDict = [NSDictionary dictionaryWithObjectsAndKeys:[movie objectForKey:@"tmdb_id"], @"tmdb_id", [movie objectForKey:@"imdb_id"],@"imdb_id",[movie objectForKey:@"year"],@"year", posterUrl,@"poster",[movie objectForKey:@"plays"],@"traktPlays",[movie objectForKey:@"title"],@"title",genres,@"genres",[movie objectForKey:@"url"],@"traktUrl", nil];
    }
    
    return argsDict;
}

- (NSDictionary *)getTVShowParameters:(NSDictionary *)serie extended:(BOOL)extended {
    
    NSString *posterUrl = [[serie objectForKey:@"images"] objectForKey:@"poster"];
    NSInteger seasons = [[[serie objectForKey:@"seasons"] objectAtIndex:0] objectForKey:@"season"];
    NSString *episodes = [[[[serie objectForKey:@"seasons"] objectAtIndex:0] objectForKey:@"episodes"] componentsJoinedByString:@","];
    NSString *genres = [[serie objectForKey:@"genres"] componentsJoinedByString:@","];
    
    NSDictionary *argsDict;
    
    if(extended) {
        
        argsDict = [NSDictionary dictionaryWithObjectsAndKeys:[serie objectForKey:@"tvdb_id"], @"tvdb_id", [serie objectForKey:@"tvrage_id"],@"tvrage_id", [serie objectForKey:@"imdb_id"],@"imdb_id",[serie objectForKey:@"year"],@"year", posterUrl,@"poster",seasons,@"seasons",episodes,@"episodes",[serie objectForKey:@"first_aired"],@"firstAired",[serie objectForKey:@"runtime"],@"runtime",[serie objectForKey:@"title"],@"title",[serie objectForKey:@"overview"],@"overview",[serie objectForKey:@"status"],@"status",[serie objectForKey:@"url"],@"traktUrl",[serie objectForKey:@"network"],@"network",[serie objectForKey:@"country"],@"country",[serie objectForKey:@"certification"],@"rating",[serie objectForKey:@"air_time"],@"airTime",[serie objectForKey:@"air_day"],@"airDay",genres,@"genres", nil];
        
    } else {
        
        argsDict = [NSDictionary dictionaryWithObjectsAndKeys:[serie objectForKey:@"tvdb_id"], @"tvdb_id", [serie objectForKey:@"tvrage_id"],@"tvrage_id", [serie objectForKey:@"imdb_id"],@"imdb_id",[serie objectForKey:@"year"],@"year", posterUrl,@"poster",seasons,@"seasons",episodes,@"episodes",[serie objectForKey:@"title"],@"title",[serie objectForKey:@"overview"],@"overview",[serie objectForKey:@"status"],@"status",[serie objectForKey:@"url"],@"traktUrl",genres,@"genres", nil];
    }

    return argsDict;
}

- (void)getMoviePoster:(NSNumber *)movieId poster:(NSString *)url {
    
    ITTVShowPoster *poster = [ITTVShowPoster new];
    
    [poster poster:movieId withUrl:url size:ITMoviePosterSizeSmall];
    [poster poster:movieId withUrl:url size:ITMoviePosterSizeMedium];
    
    // NOTE: No originals till we really need it. The image cache becomes very large very quicly with all these big images.
    //[poster poster:movieId withUrl:url size:ITMoviePosterSizeOriginal];
}

- (void)getTVShowPoster:(NSNumber *)showId poster:(NSString *)url {
    
    ITMoviePoster *poster = [ITMoviePoster new];
    
    [poster poster:showId withUrl:url size:ITTVShowPosterSizeSmall];
    [poster poster:showId withUrl:url size:ITTVShowPosterSizeMedium];
    
    // NOTE: No originals till we really need it. The image cache becomes very large very quicly with all these big images.
    //[poster poster:showId withUrl:url size:ITTVShowPosterSizeOriginal];
}

@end
