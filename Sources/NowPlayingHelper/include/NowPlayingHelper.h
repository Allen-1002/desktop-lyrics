#ifndef NOW_PLAYING_HELPER_H
#define NOW_PLAYING_HELPER_H

/// 每 0.5 秒读取一次系统“正在播放”信息，以一行 JSON 打印到标准输出。永不返回。
/// 由 /usr/bin/perl 加载调用（见 Resources/now-playing.pl）。
void dl_now_playing_loop(void);

#endif
