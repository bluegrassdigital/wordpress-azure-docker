<?php

require_once __DIR__ . '/../wordpress-plugin/wordpress-azure-monitor/includes/Logs.php';

$root = sys_get_temp_dir() . '/wazm-log-test-' . bin2hex(random_bytes(8));
$file = $root . '/access.log';
$alias = $root . '/access-current.log';

if (!mkdir($root, 0700)) {
    throw new RuntimeException('Could not create log test directory.');
}

try {
    if (file_put_contents($file, "test log entry\n") === false || !symlink($file, $alias)) {
        throw new RuntimeException('Could not create log test fixtures.');
    }

    $resolve = new ReflectionMethod(WAZM_Logs::class, 'resolve_path_within_roots');
    foreach ([
        [$file, realpath($file)],
        [$alias, realpath($file)],
        [$root, null],
        [$root . '/missing.log', null],
    ] as [$path, $expected]) {
        if ($resolve->invoke(null, $path, [realpath($root)]) !== $expected) {
            throw new RuntimeException("Unexpected result for log path: $path");
        }
    }
} finally {
    if (is_link($alias)) {
        unlink($alias);
    }
    if (is_file($file)) {
        unlink($file);
    }
    rmdir($root);
}

echo "Log path checks passed.\n";
