/**
 * Copyright (c) 2012 Martin M Reed
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#import "RecorderController.h"
#import "AppDelegate.h"

extern AppDelegate* g_appDelegate;

@implementation RecorderController

- (void)awakeFromNib
{
    QTCaptureDevice *device = [QTCaptureDevice defaultInputDeviceWithMediaType:QTMediaTypeVideo];
    if (!device)
    {
        NSLog(@"Could not find input device.");
        return;
    }
    
    BOOL success = NO;
    NSError *error;
    
    success = [device open:&error];
    if (!success || error)
    {
        NSLog(@"Could not open device.");
        NSLog(@"Error: %@", [error localizedDescription]);
        return;
    }
    
    mCaptureSession = [[QTCaptureSession alloc] init];
    [mCaptureView setCaptureSession:mCaptureSession];
    
    mCaptureDeviceInput = [[QTCaptureDeviceInput alloc] initWithDevice:device];
    success = [mCaptureSession addInput:mCaptureDeviceInput error:&error];
    if (!success || error)
    {
        NSLog(@"Could not initialize input device.");
        NSLog(@"Error: %@", [error localizedDescription]);
        return;
    }
    
    mCaptureMovieOutput = [[QTCaptureDecompressedVideoOutput alloc] init];
    success = [mCaptureSession addOutput:mCaptureMovieOutput error:&error];
    if (!success || error)
    {
        NSLog(@"Could not initialize output session.");
        NSLog(@"Error: %@", [error localizedDescription]);
        return;
    }
    
    [mCaptureMovieOutput setDelegate:self];
    [mCaptureMovieOutput setAutomaticallyDropsLateVideoFrames:TRUE];
    
    NSMutableDictionary *pixelBufferAttributes = [NSMutableDictionary dictionary];
    [pixelBufferAttributes setObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                     forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [pixelBufferAttributes setObject:[NSNumber numberWithFloat:WIDTH]
                     forKey:(id)kCVPixelBufferWidthKey];
    [pixelBufferAttributes setObject:[NSNumber numberWithFloat:HEIGHT]
                     forKey:(id)kCVPixelBufferHeightKey];
    [mCaptureMovieOutput setPixelBufferAttributes:[NSDictionary dictionaryWithDictionary:pixelBufferAttributes]];
    
    [mCaptureSession startRunning];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput didOutputVideoFrame:(CVImageBufferRef)pixelBuffer withSampleBuffer:(QTSampleBuffer *)sampleBuffer fromConnection:(QTCaptureConnection *)connection
{
    if (![g_appDelegate client_ready]) return;
    [g_appDelegate ffe_context]->add_frame(pixelBuffer);
}

- (void)windowWillClose:(NSNotification *)notification
{
    [mCaptureSession stopRunning];
    [[mCaptureDeviceInput device] close];
}

- (void)dealloc
{
    [mCaptureSession release];
    [mCaptureDeviceInput release];
    [mCaptureMovieOutput release];
    
    [super dealloc];
}

@end
