#include "PrivilegedExecutionShim.h"

OSStatus AutomateAuthorizationExecuteWithPrivileges(
    AuthorizationRef authorization,
    const char *pathToTool,
    char * const *arguments
) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return AuthorizationExecuteWithPrivileges(
        authorization,
        pathToTool,
        kAuthorizationFlagDefaults,
        arguments,
        NULL
    );
#pragma clang diagnostic pop
}
