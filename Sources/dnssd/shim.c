#include "dnssd.h"

#ifndef __APPLE__
#include <Block/Block.h>
#endif

static void DNSSD_API
DNSServiceRegisterReplyBlockThunk(DNSServiceRef sdRef,
                                  DNSServiceFlags flags,
                                  DNSServiceErrorType errorCode,
                                  const char *name,
                                  const char *regtype,
                                  const char *domain,
                                  void *context) {
    DNSServiceRegisterReplyBlock block = (DNSServiceRegisterReplyBlock)context;
    if (block) {
        block(sdRef, flags, errorCode, name, regtype, domain);
        _Block_release(block);
    }
}

DNSSD_EXPORT
DNSServiceErrorType DNSSD_API
DNSServiceRegisterBlock(DNSServiceRef *sdRef,
                        DNSServiceFlags flags,
                        uint32_t interfaceIndex,
                        const char *name, /* may be NULL */
                        const char *regtype,
                        const char *domain, /* may be NULL */
                        const char *host,   /* may be NULL */
                        uint16_t port,      /* In network byte order */
                        uint16_t txtLen,
                        const void *txtRecord, /* may be NULL */
                        DNSServiceRegisterReplyBlock block) {
    return DNSServiceRegister(sdRef, flags, interfaceIndex, name, regtype,
                              domain, host, port, txtLen, txtRecord,
                              block ? DNSServiceRegisterReplyBlockThunk : NULL,
                              block ? _Block_copy(block) : NULL);
}
