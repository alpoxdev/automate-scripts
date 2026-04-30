#ifndef PrivilegedExecutionShim_h
#define PrivilegedExecutionShim_h

#include <Security/Authorization.h>

OSStatus AutomateAuthorizationExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *pathToTool,
    char * const *arguments
);

#endif
