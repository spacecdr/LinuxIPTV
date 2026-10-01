#include <vlc/vlc.h>
#include <zlib.h>
#include <stdlib.h>
double maciptv_ratio(libvlc_media_player_t *player) {
 unsigned w=0,h=0; if(libvlc_video_get_size(player,0,&w,&h)||!h)return 0;
 double ratio=(double)w/h; libvlc_media_t *m=libvlc_media_player_get_media(player);
 if(m){libvlc_media_track_t **tracks;unsigned n=libvlc_media_tracks_get(m,&tracks);for(unsigned i=0;i<n;i++)if(tracks[i]->i_type==libvlc_track_video){libvlc_video_track_t *v=tracks[i]->video;if(v->i_sar_num&&v->i_sar_den)ratio*= (double)v->i_sar_num/v->i_sar_den;break;}libvlc_media_tracks_release(tracks,n);}return ratio;
}
unsigned char *maciptv_gunzip(const unsigned char *data,size_t size,size_t *length){
 const size_t cap=128*1024*1024;unsigned char *out=malloc(cap);if(!out)return NULL;
 z_stream s={0};s.next_in=(Bytef*)data;s.avail_in=(uInt)size;s.next_out=out;s.avail_out=cap;
 if(inflateInit2(&s,15+32)!=Z_OK){free(out);return NULL;}int result=inflate(&s,Z_FINISH);*length=s.total_out;inflateEnd(&s);if(result!=Z_STREAM_END){free(out);return NULL;}return out;
}
