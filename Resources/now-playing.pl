#!/usr/bin/perl
# 由桌面歌词启动：加载 libNowPlayingHelper.dylib，并运行它的循环，
# 循环每 0.5 秒向标准输出打印一行“正在播放”信息（JSON）。
# 用系统自带的 perl 是因为它有读取 MediaRemote 的权限。
# 参考 ungive/mediaremote-adapter（BSD 3-Clause）。

use strict;
use warnings;
use DynaLoader;

$| = 1;

my $library = shift @ARGV or die "usage: $0 /path/to/libNowPlayingHelper.dylib\n";
my $handle = DynaLoader::dl_load_file($library, 0)
    or die "Can't load $library: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "dl_now_playing_loop")
    or die "dl_now_playing_loop not found in $library\n";
DynaLoader::dl_install_xsub("main::now_playing_loop", $symbol);
now_playing_loop();
