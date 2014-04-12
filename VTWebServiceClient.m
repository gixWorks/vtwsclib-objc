/*
 Copyright (c) 2012 MetricWise, Inc
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <CommonCrypto/CommonDigest.h>

#import "NSDictionary+URLEncoding.h"
#import "SBJsonParser.h"
#import "SBJsonWriter.h"
#import "VTWebServiceClient.h"

static void *GMContext = &GMContext;

@implementation VTWebServiceClient

-(id)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"-init is not a valid initializer for VTWebServiceClient"
                                 userInfo:nil];
}

-(id)initWithURL:(NSURL *)url
{
    if (self=[super init])
    {
        _serverURL = url;
//        [self addObserver:self forKeyPath:@"sessionName" options:NSKeyValueObservingOptionNew context:GMContext];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == GMContext) {
        if ([keyPath isEqualToString:@"sessionName"]) {
            NSLog(@"sessionName changed: %@", change);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"sessionNameChanged" object:change];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (NSDictionary *)doChallenge:(NSString *)userName
{
    NSDictionary *getDict = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"getchallenge", @"operation",
                             userName, @"username",
                             nil];
    return [self doGet:getDict];
}

- (NSDictionary *)doCreate:(NSString *)elementType elementDict:(NSDictionary *)elementDict
{
    NSDictionary *postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"create", @"operation", 
                              _sessionName, @"sessionName",
                              elementType, @"elementType", 
                              [self writeJSON:elementDict], @"element",
                              nil];
    if ([elementType isEqual:@"Documents"]) {
        NSString *filePath = [elementDict objectForKey:@"filename"];
        NSString *fileName = [filePath lastPathComponent];
        NSData *fileData = [NSData dataWithContentsOfFile:filePath];
        return [self doPostFile:postDict fileData:fileData fileName:fileName];
    } else {
        return [self doPost:postDict];
    }
}

- (NSDictionary *)doGet:(NSDictionary *)getDict
{
    NSString *urlString = [[NSString alloc] initWithFormat:@"%@/?%@", [_serverURL absoluteString], [getDict urlEncodedString]];
	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [urlRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    NSData *responseData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:nil error:nil];
    return [self parseResponse:responseData];
}

- (NSDictionary *)doLogin:(NSString *)userName accessKey:(NSString *)accessKey
{
    NSDictionary *challengeDict = [self doChallenge:userName];
    NSString *token = [[challengeDict objectForKey:@"result"] objectForKey:@"token"];
    NSString *md5Hash = [self md5:[token stringByAppendingString:accessKey]];
    NSDictionary *postDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"login", @"operation",
                              userName, @"username",
                              md5Hash, @"accessKey",
                              nil];
    NSDictionary *loginDict = [self doPost:postDict];
    _sessionName = [[loginDict objectForKey:@"result"] objectForKey:@"sessionName"];
    return loginDict;
}

- (NSDictionary *)doPost:(NSDictionary *)postDict
{
    NSString *postString = [postDict urlEncodedString];
    NSData *postData = [postString dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:_serverURL];
    [urlRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
	[urlRequest setHTTPBody:postData];
	[urlRequest setHTTPMethod:@"POST"];
    [urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"content-type"];
    NSData *responseData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:nil error:nil];
    return [self parseResponse:responseData];
}

- (NSDictionary *)doPostFile:(NSDictionary *)postDict fileData:(NSData *)fileData fileName:(NSString*)fileName
{
	NSString *boundary = @"quaixai2eezoo5nut0yo9aenuikab7Ko";
    NSMutableData *postData = [NSMutableData dataWithCapacity:[fileData length] + 1024];
    [postData appendData:[[NSString stringWithFormat:@"--%@\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    for (NSString *keyString in postDict) {
        NSString *valueString = [postDict objectForKey:keyString];
        [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\n\n%@\n", keyString, valueString] dataUsingEncoding:NSUTF8StringEncoding]];
        [postData appendData:[[NSString stringWithFormat:@"--%@\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"filename\"; filename=\"%@\"\n\n", fileName] dataUsingEncoding:NSUTF8StringEncoding]];
    [postData appendData:fileData];
    [postData appendData:[[NSString stringWithFormat:@"\n--%@--\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:_serverURL];
    [urlRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
	[urlRequest setHTTPBody:postData];
	[urlRequest setHTTPMethod:@"POST"];
    [urlRequest setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"content-type"];
    NSData *responseData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:nil error:nil];
    return [self parseResponse:responseData];
}

- (NSString *) md5:(NSString *)str {
    const char *cStr = [str UTF8String];
    unsigned char result[16];
    CC_MD5( cStr, strlen(cStr), result );
    return [[NSString stringWithFormat:
             @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
             result[0], result[1], result[2], result[3],
             result[4], result[5], result[6], result[7],
             result[8], result[9], result[10], result[11],
             result[12], result[13], result[14], result[15]
             ] lowercaseString];
}

- (NSDictionary *) parseResponse:(NSData *)responseData {
    SBJsonParser *jsonParser = [[SBJsonParser alloc] init];
    NSDictionary *responseDict = [jsonParser objectWithData:responseData];
    if (![[responseDict objectForKey:@"success"] isEqual:[NSNumber numberWithInt:1]]) {
        NSLog(@"%@", responseDict);
//        NSDictionary *errorDict = [responseDict objectForKey:@"error"];
//        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[errorDict objectForKey:@"message"] userInfo:errorDict];
    }
    return responseDict;
}

- (NSString *) writeJSON:(id)value {
    SBJsonWriter *jsonWriter = [SBJsonWriter new];
    return [jsonWriter stringWithObject:value];
}

@end
