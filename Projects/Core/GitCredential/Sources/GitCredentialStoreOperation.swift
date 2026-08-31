public enum GitCredentialStoreOperation: String, Sendable {
	case resolveAccessGroup = "resolve-access-group"
	case update
	case add
	case copyItems = "copy-items"
	case copySecret = "copy-secret"
	case delete
	case decodeDescriptor = "decode-descriptor"
	case verifyMigration = "verify-migration"
}
