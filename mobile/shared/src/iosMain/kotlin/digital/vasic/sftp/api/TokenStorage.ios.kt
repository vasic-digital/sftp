/**
 * iOS actual TokenStorage — Keychain (kSecClassGenericPassword).
 *
 * Tokens are stored as two Keychain items (access / refresh) with
 * kSecAttrAccessibleAfterFirstUnlock. Requires the Keychain Sharing
 * entitlement — credentials never land in NSUserDefaults or logs
 * (§11.4.10). Uses Security-framework SecItem* calls via cinterop.
 */
package digital.vasic.sftp.api

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import platform.CoreFoundation.CFDictionaryCreateMutable
import platform.CoreFoundation.CFDictionarySetValue
import platform.CoreFoundation.CFRelease
import platform.CoreFoundation.CFTypeRefVar
import platform.CoreFoundation.kCFAllocatorDefault
import platform.Foundation.CFBridgingRelease
import platform.Foundation.CFBridgingRetain
import platform.Foundation.NSData
import platform.Foundation.NSNumber
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.create
import platform.Foundation.dataUsingEncoding
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.SecItemUpdate
import platform.Security.errSecItemNotFound
import platform.Security.errSecSuccess
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrAccessible
import platform.Security.kSecAttrAccessibleAfterFirstUnlock
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData

@OptIn(ExperimentalForeignApi::class)
actual class TokenStorage : TokenStore {

    actual override suspend fun save(tokens: StoredTokens?) {
        if (tokens == null) {
            deleteItem(KEY_ACCESS)
            deleteItem(KEY_REFRESH)
        } else {
            putItem(KEY_ACCESS, tokens.accessToken)
            putItem(KEY_REFRESH, tokens.refreshToken)
        }
    }

    actual override suspend fun load(): StoredTokens? {
        val access = getItem(KEY_ACCESS) ?: return null
        val refresh = getItem(KEY_REFRESH) ?: return null
        return StoredTokens(access, refresh)
    }

    private fun putItem(account: String, value: String) {
        val data = (value as NSString).dataUsingEncoding(NSUTF8StringEncoding) ?: return
        val query = baseQuery(account) ?: return
        try {
            val status = memScoped {
                val update = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, null, null)
                CFDictionarySetValue(update, kSecValueData, CFBridgingRetain(data))
                val s = SecItemUpdate(query, update)
                CFRelease(update)
                s
            }
            if (status == errSecItemNotFound) {
                CFDictionarySetValue(query, kSecValueData, CFBridgingRetain(data))
                SecItemAdd(query, null)
            }
        } finally {
            CFRelease(query)
        }
    }

    private fun getItem(account: String): String? {
        val query = baseQuery(account) ?: return null
        return try {
            CFDictionarySetValue(query, kSecReturnData, CFBridgingRetain(NSNumber(bool = true)))
            CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne)
            val result = memScoped {
                val out = alloc<CFTypeRefVar>()
                val status = SecItemCopyMatching(query, out.ptr)
                if (status == errSecSuccess) out.value else null
            }
            val data = CFBridgingRelease(result) as? NSData ?: return null
            NSString.create(data = data, encoding = NSUTF8StringEncoding)?.toString()
        } finally {
            CFRelease(query)
        }
    }

    private fun deleteItem(account: String) {
        val query = baseQuery(account) ?: return
        try {
            SecItemDelete(query)
        } finally {
            CFRelease(query)
        }
    }

    private fun baseQuery(account: String) =
        CFDictionaryCreateMutable(kCFAllocatorDefault, 4, null, null)?.also { query ->
            CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword)
            CFDictionarySetValue(query, kSecAttrAccount, CFBridgingRetain(account as NSString))
            CFDictionarySetValue(query, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlock)
        }

    companion object {
        private const val KEY_ACCESS = "sftp.access_token"
        private const val KEY_REFRESH = "sftp.refresh_token"
    }
}
