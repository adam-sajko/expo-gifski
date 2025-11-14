fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=Cargo.lock");

    let lock_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.lock");
    if let Ok(contents) = std::fs::read_to_string(&lock_path) {
        let version = extract_package_version(&contents, "gifski")
            .unwrap_or_else(|| "unknown".to_string());
        println!("cargo:rustc-env=GIFSKI_CRATE_VERSION={}", version);
    } else {
        println!("cargo:rustc-env=GIFSKI_CRATE_VERSION=unknown");
    }
}

fn extract_package_version(lock_contents: &str, package_name: &str) -> Option<String> {
    let mut in_target = false;
    for line in lock_contents.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("name = ") {
            let name = trimmed
                .trim_start_matches("name = ")
                .trim_matches('"');
            in_target = name == package_name;
        } else if in_target && trimmed.starts_with("version = ") {
            let version = trimmed
                .trim_start_matches("version = ")
                .trim_matches('"');
            return Some(version.to_string());
        } else if trimmed == "[[package]]" {
            in_target = false;
        }
    }
    None
}
