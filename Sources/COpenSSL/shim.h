#ifndef COPENSSL_SHIM_H
#define COPENSSL_SHIM_H

#include <openssl/ssl.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pkcs12.h>
#include <openssl/x509.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/hmac.h>
#include <openssl/crypto.h>
#include <openssl/rand.h>
#include <stddef.h>

// Re-publish OpenSSL macro-control APIs as ordinary functions so the Swift
// importer sees clean signatures.

static inline size_t COpenSSL_BIO_pending(BIO *b) {
  return (size_t)BIO_pending(b);
}

static inline int COpenSSL_SSL_CTX_set_min_proto_version(SSL_CTX *ctx, int version) {
  return (int)SSL_CTX_set_min_proto_version(ctx, version);
}

static inline int COpenSSL_SSL_CTX_set_max_proto_version(SSL_CTX *ctx, int version) {
  return (int)SSL_CTX_set_max_proto_version(ctx, version);
}

static inline long COpenSSL_SSL_CTX_add_extra_chain_cert(SSL_CTX *ctx, X509 *cert) {
  return SSL_CTX_add_extra_chain_cert(ctx, cert);
}

// STACK_OF(X509) is itself a macro; we take void * and cast.
static inline int COpenSSL_sk_X509_num(void *sk) {
  return sk_X509_num((const STACK_OF(X509) *)sk);
}

static inline X509 *COpenSSL_sk_X509_value(void *sk, int idx) {
  return sk_X509_value((const STACK_OF(X509) *)sk, idx);
}

static inline void COpenSSL_sk_X509_pop_free(void *sk) {
  sk_X509_pop_free((STACK_OF(X509) *)sk, X509_free);
}

static inline int COpenSSL_SSL_get_ex_new_index(long argl, void *argp,
                                                CRYPTO_EX_new *new_func,
                                                CRYPTO_EX_dup *dup_func,
                                                CRYPTO_EX_free *free_func) {
  return SSL_get_ex_new_index(argl, argp, new_func, dup_func, free_func);
}

static inline long COpenSSL_SSL_set_tlsext_host_name(SSL *ssl, const char *name) {
  return SSL_set_tlsext_host_name(ssl, name);
}

static inline long COpenSSL_SSL_set_mtu(SSL *ssl, long mtu) {
  return SSL_set_mtu(ssl, mtu);
}

static inline long COpenSSL_DTLSv1_handle_timeout(SSL *ssl) {
  return DTLSv1_handle_timeout(ssl);
}

static inline long COpenSSL_DTLSv1_get_timeout(SSL *ssl, struct timeval *tv) {
  return DTLSv1_get_timeout(ssl, tv);
}

static const uint64_t COpenSSL_SSL_OP_COOKIE_EXCHANGE = SSL_OP_COOKIE_EXCHANGE;
static const uint64_t COpenSSL_SSL_OP_NO_RENEGOTIATION = SSL_OP_NO_RENEGOTIATION;
static const uint64_t COpenSSL_SSL_OP_CIPHER_SERVER_PREFERENCE = SSL_OP_CIPHER_SERVER_PREFERENCE;
static const uint64_t COpenSSL_SSL_OP_NO_TICKET = SSL_OP_NO_TICKET;

static inline int COpenSSL_SSL_CTX_set_max_early_data(SSL_CTX *ctx, uint32_t max) {
  return SSL_CTX_set_max_early_data(ctx, max);
}

static inline X509 *COpenSSL_SSL_get_peer_certificate(const SSL *ssl) {
  return SSL_get_peer_certificate(ssl);
}

static inline int COpenSSL_X509_digest_sha256(X509 *cert, unsigned char *out, unsigned int *outlen) {
  return X509_digest(cert, EVP_sha256(), out, outlen);
}

static inline long COpenSSL_SSL_CTX_set_mode(SSL_CTX *ctx, long mode) {
  return SSL_CTX_set_mode(ctx, mode);
}

static inline int COpenSSL_BIO_reset(BIO *b) {
  return BIO_reset(b);
}

static const long COpenSSL_SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER = SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER;
static const long COpenSSL_SSL_MODE_ENABLE_PARTIAL_WRITE = SSL_MODE_ENABLE_PARTIAL_WRITE;

// CRL revocation checking. CRL_CHECK validates the leaf; CRL_CHECK_ALL
// extends to every intermediate as well — opt-in via the public
// `Ocp1TLSRevocationOptions.chainWide` flag.
static inline int COpenSSL_X509_STORE_add_crl(X509_STORE *store, X509_CRL *crl) {
  return X509_STORE_add_crl(store, crl);
}

static inline int COpenSSL_X509_STORE_set_flags(X509_STORE *store, unsigned long flags) {
  return X509_STORE_set_flags(store, flags);
}

static const unsigned long COpenSSL_X509_V_FLAG_CRL_CHECK = X509_V_FLAG_CRL_CHECK;
static const unsigned long COpenSSL_X509_V_FLAG_CRL_CHECK_ALL = X509_V_FLAG_CRL_CHECK_ALL;

#endif /* COPENSSL_SHIM_H */
