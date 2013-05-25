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

#import <Cocoa/Cocoa.h>

#include "cmdr_client.h"
#include "bps_tracker.h"
#include "ffbbenc.h"
#include "ffbbdec.h"
#include "packet_sender.h"

#include <pthread.h>
#include <map>
#include <deque>

#define WIDTH 288
#define HEIGHT 512

void connected_callback(void *cookie);
void frame_index_callback(int index, void* cookie);

void ffe_context_close(ffenc_context *ffe_context, void *arg);
void ffe_write_callback(ffenc_context *ffe_context, uint8_t *buf, ssize_t size, void *arg);
bool ffe_frame_callback(ffenc_context *ffe_context, AVFrame *frame, int index, void *arg);

void ffd_context_close(ffdec_context *ffd_context, void *arg);
int ffd_read_callback(ffdec_context *ffd_context, uint8_t *buf, ssize_t size, void *arg);
void ffd_frame_callback(ffdec_context *ffd_context, AVFrame *frame, int index, void *arg);

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    cmdr::cmdr_client *client;
    bool client_ready;
    pthread_mutex_t connected_mutex;
    pthread_cond_t connected_cond;
    
    ffenc_context *ffe_context;
    std::map<int, long> frame_indices;
    cmdr::bps_tracker* bps_tracker_enc;
    std::deque<long> fps_enc;
    
    ffdec_context *ffd_context;
    cmdr::bps_tracker* bps_tracker_dec;
    std::deque<long> fps_dec;
    
    cmdr::packet_sender* frame_index_sender;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign, readonly) ffenc_context *ffe_context;
@property (assign, readonly) bool client_ready;

- (bool)start_encoder:(CodecID)codec_id;
- (bool)start_decoder:(CodecID)codec_id;
- (void)update_fps:(std::deque<long>&)fps timestamp:(long)timestamp;
- (void)print_fps:(long)timestamp;

@end
