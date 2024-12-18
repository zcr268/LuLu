//
//  BlockOrAllowList.m
//  Extension
//
//  Created by Patrick Wardle on 11/6/20.
//  Copyright © 2020 Objective-See. All rights reserved.
//

#import "consts.h"
#import "Preferences.h"
#import "BlockOrAllowList.h"

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//preferences
extern Preferences* preferences;

@implementation BlockOrAllowList

-(id)init:(NSString*)path
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //save list
        self.path = path;
        
        //load
        [self load:self.path];
    }
    
    return self;
}

//was specified block list remote
// ...just checks if prefixed with http:// || https://
-(BOOL)isRemote
{
    //specified path a URL?
    return ((YES == [self.path hasPrefix:@"http://"]) || (YES == [self.path hasPrefix:@"https://"]));
}

//should reload
// checks file modification time
-(BOOL)shouldReload
{
    //flag
    BOOL shouldReload = NO;
    
    //current mod. time
    NSDate* modified = nil;
    
    //if it's remote
    // can't tell, so default to no
    if(YES == [self isRemote])
    {
        //bail
        goto bail;
    }
    
    //get modified timestamp
    modified = [[NSFileManager.defaultManager attributesOfItemAtPath:self.path error:nil] objectForKey:NSFileModificationDate];

    //was file modified?
    if(NSOrderedDescending == [modified compare:self.lastModified])
    {
        //dbg msg
        os_log_debug(logHandle, "block list was modified ...will reload");
        
        //yes
        shouldReload = YES;
    }
    
bail:
    
    return shouldReload;
}

//(re)load
-(void)load:(NSString*)path;
{
    //error
    NSError* error = nil;
    
    //file contents
    NSString* list = nil;
    
    //sync
    @synchronized (self) {
        
    //update path
    self.path = path;
        
    //reset list
    [self.items removeAllObjects];
        
    //dbg msg
    os_log_debug(logHandle, "%s", __PRETTY_FUNCTION__);
    
    //check
    // path?
    if(0 == self.path.length)
    {
        //dbg msg
        os_log_debug(logHandle, "no list specified...");
        
        //bail
        goto bail;
    }
        
    //remote?
    // load via URL
    if(YES == [self isRemote])
    {
        //dbg msg
        os_log_debug(logHandle, "(re)loading (remote) list");
        
        //load
        list = [NSString stringWithContentsOfURL:[NSURL URLWithString:self.path] encoding:NSUTF8StringEncoding error:&error];
        if(nil != error)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to (re)load (remote) list, %{public}@ (error: %{public}@)", self.path, error);
            
            //bail
            goto bail;
        }
        
        //(re)load remote URL once a day
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(24 * 60 * 60 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            
            //dbg msg
            os_log_debug(logHandle, "(re)loading (remote) list");
            
            //(re)load
            [self load:self.path];
            
        });
    }
    
    //local file
    // check and load
    else
    {
        //dbg msg
        os_log_debug(logHandle, "(re)loading (local) list, %{public}@", self.path);
            
        //(re)load
        list = [NSString stringWithContentsOfFile:self.path encoding:NSUTF8StringEncoding error:&error];
        if(nil != error)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to (re)load (local) list, %{public}@ (error: %{public}@)", self.path, error);
            
            //bail
            goto bail;
        }
        
        //save timestamp
        self.lastModified = [[NSFileManager.defaultManager attributesOfItemAtPath:self.path error:nil] objectForKey:NSFileModificationDate];
    }
     
    //now alloc
    self.items = [NSMutableArray array];
    
    //parse/check each
    for(NSString* item in [list componentsSeparatedByString:@"\n"])
    {
        //skip empty items
        if(0 == item.length)
        {
            continue;
        }
        
        //skip commands
        if(YES == [item hasPrefix:@"#"])
        {
            continue;
        }
        
        //add
        [self.items addObject:item];
    }
    
    //dbg msg
    os_log_debug(logHandle, "(re)loaded %lu list items", (unsigned long)self.items.count);
    
    } //sync

bail:
    
    return;
}

//check if flow matches item on block or allow list
-(BOOL)isMatch:(NEFilterSocketFlow*)flow
{
    //match
    BOOL isMatch = NO;
    
    //remote endpoint
    NWHostEndpoint* remoteEndpoint = nil;
    
    //endpoint url/hosts
    NSMutableArray* endpointNames = nil;
    
    //extract remote endpoint
    remoteEndpoint = (NWHostEndpoint*)flow.remoteEndpoint;
    
    //need to reload list?
    // checks timestamp to see if modified
    if(YES == [self shouldReload])
    {
        //(re)load list
        [self load:self.path];
    }
    
    //sync
    @synchronized (self) {
        
    //init endpoint names
    endpointNames = [NSMutableArray array];
        
    //add url
    if(nil != flow.URL.absoluteString)
    {
        //add full url
        [endpointNames addObject:flow.URL.absoluteString];
    }
    
    //add host
    if(nil != flow.URL.host)
    {
        //add full url
        [endpointNames addObject:flow.URL.host];
    }
        
    //add host name
    if(nil != remoteEndpoint.hostname)
    {
        //add
        [endpointNames addObject:remoteEndpoint.hostname];
    }
    
    //macOS 11+?
    // add remote host name
    if(@available(macOS 11, *))
    {
        //add remote host name
        if(nil != flow.remoteHostname)
        {
            //add
            [endpointNames addObject:flow.remoteHostname];
        }
    }

    //check each item
    for(NSString* item in self.items)
    {
        //check against each name
        for(NSString* endpointName in endpointNames)
        {
            //match?
            if(NSOrderedSame == [item caseInsensitiveCompare:endpointName])
            {
                //dbg msg
                os_log_debug(logHandle, "listed item '%{public}@' matches %{public}@", item, endpointNames);
                
                //happy
                isMatch = YES;
                
                //done
                goto bail;
            }
        }
    }
        
    }//sync
    
bail:
    
    return isMatch;
}

@end