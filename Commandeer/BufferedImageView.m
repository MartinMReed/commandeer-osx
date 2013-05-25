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

#import "BufferedImageView.h"

extern BufferedImageView* g_bufferedImageView;

#define WIDTH 288
#define HEIGHT 512

@implementation BufferedImageView

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        image_buffer = (unsigned char*) malloc(HEIGHT * WIDTH * 4 * sizeof(unsigned char));
        g_bufferedImageView = self;
    }
    return self;
}

- (void)dealloc
{
    free(image_buffer);
    
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef frameContext = CGBitmapContextCreate(NULL, WIDTH, HEIGHT, 8, WIDTH * 4, rgbColorSpace, kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(rgbColorSpace);
    
    unsigned char* data = CGBitmapContextGetData(frameContext);
    memcpy(data, image_buffer, WIDTH * HEIGHT * 4);
        
    CGImageRef frameImage = CGBitmapContextCreateImage(frameContext);
    CGContextDrawImage([[NSGraphicsContext currentContext] graphicsPort], CGRectMake(0, 0, WIDTH, HEIGHT), frameImage);
    CGImageRelease(frameImage);
    CGContextRelease(frameContext);
}

@end
