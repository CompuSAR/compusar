#pragma once

#define abortWithMessage(msg) _abortWithMessage((msg), __FILE__, __LINE__)
#define assertWithMessage(condition, msg ) _assertWithMessage((condition), (msg), __FILE__, __LINE__)
#define checkWithMessage(condition, msg ) _checkWithMessage((condition), (msg), __FILE__, __LINE__)

[[noreturn]] void _abortWithMessage( const char *message, const char *file, int line );
void _assertWithMessage( bool condition, const char *message, const char *file, int line );
void _checkWithMessage( bool condition, const char *message, const char *file, int line );
