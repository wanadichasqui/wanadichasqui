use storage::{open_encrypted_db, init_schema, upsert_identity, get_identity, export_storage, import_storage, Identity};
use tempfile::NamedTempFile;
use serde_json::json;

#[test]
fn test_storage_vault_flow() {
    let temp_db = NamedTempFile::new().unwrap();
    let db_path = temp_db.path();
    let master_pwd = "super-secret-master-password";

    // 1. Abre y crea la DB
    let conn = open_encrypted_db(db_path, master_pwd).unwrap();
    init_schema(&conn).unwrap();

    // Verificamos que se haya creado el archivo .salt
    let salt_path = db_path.with_extension("salt");
    assert!(salt_path.exists());
    let salt_bytes = std::fs::read(&salt_path).unwrap();
    assert_eq!(salt_bytes.len(), 16);

    // 2. Inserta una identidad
    let ident = Identity {
        id: 1,
        clave_pub: "pubkey-alice-123456789".to_string(),
        alias_local: Some("Alice".to_string()),
        metadata: json!({ "device": "iPhone" }),
        claves_efem: vec!["session-key-1".to_string(), "session-key-2".to_string()],
    };
    upsert_identity(&conn, &ident).unwrap();

    // 3. Recupera la identidad
    let retrieved = get_identity(&conn, 1).unwrap().expect("identity not found");
    assert_eq!(retrieved.id, 1);
    assert_eq!(retrieved.clave_pub, "pubkey-alice-123456789");
    assert_eq!(retrieved.alias_local, Some("Alice".to_string()));
    assert_eq!(retrieved.metadata["device"], "iPhone");
    assert_eq!(retrieved.claves_efem, vec!["session-key-1".to_string(), "session-key-2".to_string()]);

    drop(conn);

    // 4. Exporta a un archivo cifrado
    let temp_export = NamedTempFile::new().unwrap();
    let export_path = temp_export.path();
    let export_pwd = "export-passphrase-abc";
    export_storage(db_path, master_pwd, export_pwd, export_path).unwrap();

    // 5. Importa a otra base de datos
    let temp_db_imported = NamedTempFile::new().unwrap();
    let db_imported_path = temp_db_imported.path();
    let imported_master_pwd = "new-master-password";
    import_storage(export_path, export_pwd, db_imported_path, imported_master_pwd).unwrap();

    // Verificamos que se haya creado el salt de la DB importada
    let salt_imported_path = db_imported_path.with_extension("salt");
    assert!(salt_imported_path.exists());

    // 6. Abre la DB importada y comprueba la identidad
    let conn_imported = open_encrypted_db(db_imported_path, imported_master_pwd).unwrap();
    let retrieved_imported = get_identity(&conn_imported, 1).unwrap().expect("imported identity not found");
    assert_eq!(retrieved_imported.clave_pub, "pubkey-alice-123456789");
    assert_eq!(retrieved_imported.alias_local, Some("Alice".to_string()));
}

#[test]
fn test_migrations() {
    let temp_db = NamedTempFile::new().unwrap();
    let db_path = temp_db.path();
    let master_pwd = "password-for-migrations";

    // Abre la base y corre las migraciones automáticamente
    let conn = open_encrypted_db(db_path, master_pwd).unwrap();
    init_schema(&conn).unwrap();
    
    // Verificamos la versión de esquema alcanzada
    let user_version: i32 = conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
    assert_eq!(user_version, 2);

    // Verificamos que la columna 'is_verified' existe en la tabla contactos
    let has_col: bool = conn.query_row(
        "SELECT count(*) FROM pragma_table_info('contactos') WHERE name='is_verified'",
        [],
        |row| row.get::<_, i32>(0).map(|c| c > 0)
    ).unwrap();
    assert!(has_col);
}

