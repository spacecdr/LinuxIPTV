#include <stdint.h>
typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;
libvlc_instance_t *libvlc_new(int, const char *const *);
void libvlc_release(libvlc_instance_t *);
libvlc_media_t *libvlc_media_new_location(libvlc_instance_t *, const char *);
void libvlc_media_add_option(libvlc_media_t *, const char *);
void libvlc_media_release(libvlc_media_t *);
libvlc_media_player_t *libvlc_media_player_new(libvlc_instance_t *);
void libvlc_media_player_release(libvlc_media_player_t *);
void libvlc_media_player_set_nsobject(libvlc_media_player_t *, void *);
void libvlc_media_player_set_media(libvlc_media_player_t *, libvlc_media_t *);
int libvlc_media_player_play(libvlc_media_player_t *);
void libvlc_media_player_stop(libvlc_media_player_t *);
void libvlc_media_player_pause(libvlc_media_player_t *);
int libvlc_media_player_get_state(libvlc_media_player_t *);
int64_t libvlc_media_player_get_time(libvlc_media_player_t *);
int libvlc_audio_set_volume(libvlc_media_player_t *, int);
void libvlc_audio_set_mute(libvlc_media_player_t *, int);
void libvlc_video_set_key_input(libvlc_media_player_t *, unsigned);
void libvlc_video_set_mouse_input(libvlc_media_player_t *, unsigned);
unsigned libvlc_media_player_has_vout(libvlc_media_player_t *);
int libvlc_video_get_size(libvlc_media_player_t *, unsigned, unsigned *, unsigned *);
#include <stddef.h>
double maciptv_ratio(libvlc_media_player_t *);
unsigned char *maciptv_gunzip(const unsigned char *, size_t, size_t *);
