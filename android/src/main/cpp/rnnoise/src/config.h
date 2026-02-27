/* Minimal config.h for Android NDK compilation */
#ifndef CONFIG_H
#define CONFIG_H

#define HAVE_CONFIG_H 1
#define PACKAGE "rnnoise"
#define VERSION "0.2"

/* Disable x86 intrinsics on ARM */
#if !defined(__x86_64__) && !defined(__i386__)
#define DISABLE_DOT_PROD
#endif

#endif /* CONFIG_H */
