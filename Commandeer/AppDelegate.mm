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

#import "AppDelegate.h"
#import "BufferedImageView.h"

#include "time/_time.h"

AppDelegate* g_appDelegate;
BufferedImageView* g_bufferedImageView;

@implementation AppDelegate

@synthesize ffe_context;
@synthesize client_ready;

- (id)init
{
    self = [super init];
    if (self) {
        g_appDelegate = self;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    ffe_context = new ffenc_context();
    ffd_context = new ffdec_context();
    
    bps_tracker_enc = new cmdr::bps_tracker();
    bps_tracker_dec = new cmdr::bps_tracker();
    
    pthread_mutex_init(&connected_mutex, 0);
    pthread_cond_init(&connected_cond, 0);
    
    client_ready = false;
    
    client = new cmdr::cmdr_client("127.0.0.1", 1031, "2", "1");
    client->connected_callback = connected_callback;
    client->connected_callback_cookie = self;
    client->frame_index_callback = frame_index_callback;
    client->frame_index_callback_cookie = self;
    client->start();
    
    frame_index_sender = new cmdr::packet_sender();
}

- (void)dealloc
{
    delete frame_index_sender;
    
    delete client;
    delete bps_tracker_dec;
    
    delete ffe_context;
    delete ffd_context;
    
    [super dealloc];
}

void connected_callback(void *cookie)
{
    AppDelegate* app = (AppDelegate*) cookie;
    if (![app start_encoder:CODEC_ID_MPEG2VIDEO]) return;
    if (![app start_decoder:CODEC_ID_MPEG2VIDEO])
    {
        app->ffe_context->close();
        return;
    }
    app->client_ready = true;
    pthread_cond_signal(&app->connected_cond);
}

void frame_index_callback(int index, void* cookie)
{
    AppDelegate* app = (AppDelegate*) cookie;
    
    std::map<int, long>::iterator i = app->frame_indices.find(index);
    
    if (i == app->frame_indices.end())
    {
        fprintf(stderr,"Could not find timestamp for frame %d\n", index);
    }
    else app->frame_indices.erase(i);
}

void ffe_context_close(ffenc_context *ffe_context, void *arg)
{
    ffe_context->close();
    
    AppDelegate* app = (AppDelegate*) arg;
    app->client_ready = false;
    
    cmdr::cmdr_client *cmdr_client = app->client;
    cmdr_client->disconnect();
}

void ffd_context_close(ffdec_context *ffd_context, void *arg)
{
    ffd_context->close();
}

int ffd_read_callback(ffdec_context *ffd_context, uint8_t *buf, ssize_t size, void *arg)
{
    AppDelegate* app = (AppDelegate*) arg;
    
    if (!app->client_ready)
    {
        pthread_mutex_lock(&app->connected_mutex);
        if (!app->client_ready) pthread_cond_wait(&app->connected_cond, &app->connected_mutex);
        pthread_mutex_unlock(&app->connected_mutex);
    }
    
    cmdr::cmdr_client *cmdr_client = app->client;
    int r = read(cmdr_client->data_channel, buf, size);
    app->bps_tracker_dec->update(r);
    return r;
}

void ffe_write_callback(ffenc_context *ffe_context, uint8_t *buf, ssize_t size, void *arg)
{
    AppDelegate* app = (AppDelegate*) arg;
    
    if (!app->client_ready)
    {
        pthread_mutex_lock(&app->connected_mutex);
        if (!app->client_ready) pthread_cond_wait(&app->connected_cond, &app->connected_mutex);
        pthread_mutex_unlock(&app->connected_mutex);
    }
    
    cmdr::cmdr_client *cmdr_client = app->client;
    
    int o = 0;
    do
    {
        int w = ::write(cmdr_client->data_channel, &buf[o], (size - o) * sizeof(uint8_t));
        if (w < 0) break;
        o += w;
    }
    while (o < size);
    
    app->bps_tracker_enc->update(o);
}

bool ffe_frame_callback(ffenc_context *ffe_context, AVFrame *frame, int index, void *arg)
{
    AppDelegate* app = (AppDelegate*) arg;
    long timestamp = hbc::current_time_millis();
    [app update_fps:app->fps_enc timestamp:timestamp];
    return true;
}

void ffd_frame_callback(ffdec_context *ffd_context, AVFrame *frame, int index, void *arg)
{
    AppDelegate* app = (AppDelegate*) arg;
    
    cmdr::cmdr_client *cmdr_client = app->client;
    hbc::socket_packet* packet = cmdr_client->build_last_frame_index(index);
    cmdr::packet_sender* packet_sender = app->frame_index_sender;
    packet_sender->send(packet);
    
    unsigned char *image_buffer = g_bufferedImageView->image_buffer;
    yuv_to_rgb(frame, image_buffer, WIDTH, HEIGHT);
    
    [g_bufferedImageView display];
    
    long timestamp = hbc::current_time_millis();
    [app update_fps:app->fps_dec timestamp:timestamp];
    [app print_fps:timestamp];
}

- (bool)start_encoder:(CodecID)codec_id
{
    AVCodec *codec = avcodec_find_encoder(codec_id);
    
    if (!codec)
    {
        av_register_all();
        codec = avcodec_find_encoder(codec_id);
        
        if (!codec)
        {
            fprintf(stderr, "could not find codec\n");
            return false;
        }
    }
    
    AVCodecContext *codec_context = avcodec_alloc_context3(codec);
    codec_context->pix_fmt = PIX_FMT_YUV420P;
    codec_context->width = WIDTH;
    codec_context->height = HEIGHT;
    codec_context->bit_rate = 400000;
    codec_context->time_base.num = 1;
    codec_context->time_base.den = 30;
    codec_context->ticks_per_frame = 2;
    codec_context->gop_size = 15;
    codec_context->colorspace = AVCOL_SPC_SMPTE170M;
    codec_context->thread_count = 2;
    
    ffe_context->reset();
    ffe_context->set_close_callback(ffe_context_close, self);
    ffe_context->set_write_callback(ffe_write_callback, self);
    ffe_context->set_frame_callback(ffe_frame_callback, self);
    ffe_context->codec_context = codec_context;
    
    frame_indices.clear();
    
    if (avcodec_open2(codec_context, codec, NULL) < 0)
    {
        av_free(codec_context);
        fprintf(stderr, "could not open codec context\n");
        return false;
    }
    
    if (ffe_context->start() != FFENC_OK)
    {
        fprintf(stderr, "could not start ffenc\n");
        ffe_context->close();
        return false;
    }
    
    return true;
}

- (bool)start_decoder:(CodecID)codec_id
{
    AVCodec *codec = avcodec_find_decoder(codec_id);
    
    if (!codec)
    {
        av_register_all();
        codec = avcodec_find_decoder(codec_id);
        
        if (!codec)
        {
            fprintf(stderr, "could not find codec\n");
            return false;
        }
    }
    
    AVCodecContext *codec_context = avcodec_alloc_context3(codec);
    codec_context->pix_fmt = PIX_FMT_YUV420P;
    codec_context->width = WIDTH;
    codec_context->height = HEIGHT;
    codec_context->thread_count = 2;
    
    if (codec->capabilities & CODEC_CAP_TRUNCATED)
    {
        // we do not send complete frames
        codec_context->flags |= CODEC_FLAG_TRUNCATED;
    }
    
    ffd_context->reset();
    ffd_context->set_frame_callback(ffd_frame_callback, self);
    ffd_context->set_close_callback(ffd_context_close, self);
    ffd_context->set_read_callback(ffd_read_callback, self);
    ffd_context->codec_context = codec_context;
    
    if (avcodec_open2(codec_context, codec, NULL) < 0)
    {
        av_free(codec_context);
        fprintf(stderr, "could not open codec context\n");
        return false;
    }
    
    if (ffd_context->start() != FFDEC_OK)
    {
        fprintf(stderr, "could not start ffdec\n");
        ffd_context->close();
        return false;
    }
    
    return true;
}

- (void)update_fps:(std::deque<long>&)fps timestamp:(long)timestamp
{
    fps.push_back(timestamp);
    while (fps.back() - fps.front() > 1000)
    {
        fps.pop_front();
    }
}

- (void)print_fps:(long)timestamp
{
    static long last_timestamp = timestamp;
    if (timestamp - last_timestamp < 1000)
    {
        return;
    }
    
    last_timestamp = timestamp;
    
    long longest_wait = 0;
    
    if (frame_indices.size())
    {
        std::map<int, long>::iterator i;
        for (i = frame_indices.begin(); i != frame_indices.end(); i++)
        {
            if (!longest_wait) longest_wait = i->second;
            longest_wait = std::min(longest_wait, i->second);
        }
        
        longest_wait = timestamp - longest_wait;
    }
    
    double w;
    cmdr::bps_type w_typ = bps_tracker_enc->get_bps(&w);
    
    double r;
    cmdr::bps_type r_typ = bps_tracker_dec->get_bps(&r);
    
    NSLog(@"fps_dec[%d], fps_enc[%d], read[%.2f%s], write[%.2f%s], in_transit[%d], wait[%ldms]\n",
            fps_dec.size(), fps_enc.size(),
            r_typ == cmdr::none ? 0 : r, cmdr::bps_type_str(r_typ),
            w_typ == cmdr::none ? 0 : w, cmdr::bps_type_str(w_typ),
            frame_indices.size(), longest_wait);
}

@end
