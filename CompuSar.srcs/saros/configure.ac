#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ([2.71])
AC_INIT([saros],[0.01])
AM_INIT_AUTOMAKE([foreign])
AC_CONFIG_SRCDIR([bl1/start.s])

# Checks for programs.
AC_LANG(C++)
AC_PROG_CXX
AC_PROG_RANLIB
AM_PROG_AS

CXXFLAGS="-g -std=c++23 -fno-exceptions -O2"
LDFLAGS="-g"

# Checks for libraries.

# Checks for header files.

# Checks for typedefs, structures, and compiler characteristics.

# Checks for library functions.

AC_CONFIG_FILES([Makefile
                 bl1/Makefile
                 saros/Makefile
                 saros/kernel/Makefile])

AC_SUBST([HOST_TRIPLET], [$host])

AC_OUTPUT
