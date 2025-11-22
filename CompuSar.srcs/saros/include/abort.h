#pragma once

[[noreturn]] void abortWithMessage( const char *message );
void assertWithMessage( bool condition, const char *message );
void checkWithMessage( bool condition, const char *message );
