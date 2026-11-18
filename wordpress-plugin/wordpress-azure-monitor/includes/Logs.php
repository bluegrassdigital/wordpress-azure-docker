<?php

class WAZM_Logs
{
    /**
     * Cache duration in seconds
     */
    private const CACHE_DURATION = 60; // 1 minute for log metadata

    /**
     * Cache key for whitelisted logs
     */
    private const CACHE_KEY = 'wazm_whitelisted_logs';

    /**
     * Resolve a log path and allow only readable regular files under the log roots.
     * Symlinks are allowed when their final target remains inside an approved root.
     */
    public static function resolve_log_path(string $path): ?string
    {
        return self::resolve_path_within_roots($path, ['/home/LogFiles', '/homelive/LogFiles']);
    }

    /**
     * Resolve a log path under the supplied roots. Kept private so callers cannot
     * widen the production allowlist; tests may exercise it through reflection.
     */
    private static function resolve_path_within_roots(string $path, array $roots): ?string
    {
        // PHP stream wrappers are not valid filesystem log paths.
        if (strpos($path, '://') !== false) {
            return null;
        }

        clearstatcache(true, $path);
        $resolved = realpath($path);
        if ($resolved === false || !is_file($resolved) || !is_readable($resolved)) {
            return null;
        }

        foreach ($roots as $root) {
            $root = rtrim($root, '/') . '/';
            if (strpos($resolved, $root) === 0) {
                return $resolved;
            }
        }

        return null;
    }

    /**
     * Whitelist of allowed log files with strict path validation
     * @return array
     */
    public static function get_whitelisted_logs(): array
    {
        // Try to get from cache first
        $cached = wp_cache_get(self::CACHE_KEY, 'wazm');
        if (is_array($cached)) {
            $validated = [];
            foreach ($cached as $key => $meta) {
                if (!is_array($meta) || !isset($meta['path']) || !is_string($meta['path'])) {
                    continue;
                }

                $resolved = self::resolve_log_path($meta['path']);
                if ($resolved === null) {
                    continue;
                }

                $size = filesize($resolved);
                if ($size === false || $size > 50 * 1024 * 1024) {
                    continue;
                }

                $validated[$key] = [
                    'label' => isset($meta['label']) ? (string) $meta['label'] : (string) $key,
                    'path' => $resolved,
                ];
            }

            // Cached paths may have changed since they were listed; return only safe targets.
            return $validated;
        }

        // Prefer homelive paths (sync-enabled) and fall back to home variants
        $candidates = [
            'apache-access'   => ['/homelive/LogFiles/sync/apache2/access.log', '/home/LogFiles/sync/apache2/access.log'],
            'apache-error'    => ['/homelive/LogFiles/sync/apache2/error.log',  '/home/LogFiles/sync/apache2/error.log'],
            'php-error'       => ['/homelive/LogFiles/sync/apache2/php-error.log','/home/LogFiles/sync/apache2/php-error.log'],
            // Prefer /home for cron since writers append there; include homelive as fallback snapshot
            // If homelive exists and is non-empty, prefer it (sync enabled path)
            'cron'            => ['/homelive/LogFiles/sync/cron.log', '/home/LogFiles/sync/cron.log', '/home/LogFiles/cron.log'],
            // Unison runtime log (written by supervisord program:sync) — prefer homelive
            'sync'            => ['/homelive/LogFiles/sync/unison.log', '/home/LogFiles/sync/unison.log'],
            // Supervisord master log (support both roots)
            'supervisord'     => ['/home/LogFiles/supervisord.log', '/homelive/LogFiles/supervisord.log'],
        ];

        // Resolve latest per-run sync-init logs without relying on symlinks
        $latestSyncInit = self::find_latest_run([
            '/home/LogFiles/sync/runs/sync-init-*.log',
            '/homelive/LogFiles/sync/runs/sync-init-*.log',
        ]);
        if ($latestSyncInit !== null) {
            $candidates['sync-init'] = [$latestSyncInit];
        } else {
            // Fallback to legacy symlinks if scan fails
            $candidates['sync-init'] = ['/homelive/LogFiles/sync-init.log', '/home/LogFiles/sync-init.log'];
        }

        $latestSyncInitErr = self::find_latest_run([
            '/home/LogFiles/sync/runs/sync-init-error-*.log',
            '/homelive/LogFiles/sync/runs/sync-init-error-*.log',
        ]);
        if ($latestSyncInitErr !== null) {
            $candidates['sync-init-error'] = [$latestSyncInitErr];
        } else {
            $candidates['sync-init-error'] = ['/homelive/LogFiles/sync-init-error.log', '/home/LogFiles/sync-init-error.log'];
        }

        $labels = [
            'apache-access' => 'Apache Access',
            'apache-error' => 'Apache Error',
            'php-error' => 'PHP Error',
            'cron' => 'Cron',
            'sync' => 'Sync',
            'supervisord' => 'Supervisord',
            'sync-init' => 'Sync Init',
            'sync-init-error' => 'Sync Init (stderr)',
        ];

        $map = [];
        foreach ($candidates as $key => $paths) {
            foreach ($paths as $p) {
                $resolved = self::resolve_log_path($p);
                if ($resolved === null) {
                    continue;
                }

                if ($key === 'cron') {
                    // For cron, require non-empty file to avoid preferring a 0B placeholder
                    $size = filesize($resolved);
                    if ($size === false || $size === 0) {
                        continue;
                    }
                }

                $map[$key] = [
                    'label' => $labels[$key],
                    'path' => $resolved,
                ];
                break; // prefer the first safe, existing candidate
            }
        }

        // Only include files that exist and are readable
        foreach ($map as $key => $meta) {
            $resolved = self::resolve_log_path($meta['path']);
            if ($resolved === null) {
                unset($map[$key]);
                continue;
            }

            $map[$key]['path'] = $resolved;

            // Check file size (max 50MB)
            $size = filesize($resolved);
            if ($size === false || $size > 50 * 1024 * 1024) {
                unset($map[$key]);
                continue;
            }
        }

        // Cache the result
        wp_cache_set(self::CACHE_KEY, $map, 'wazm', self::CACHE_DURATION);

        return $map;
    }

    /**
     * Find the most recent file matching any of the provided glob patterns.
     * Returns null if none found or unreadable.
     */
    private static function find_latest_run(array $patterns): ?string
    {
        $candidates = [];
        foreach ($patterns as $pattern) {
            $matches = glob($pattern) ?: [];
            foreach ($matches as $m) {
                $resolved = self::resolve_log_path($m);
                if ($resolved !== null) {
                    $mtime = @filemtime($resolved) ?: 0;
                    $candidates[$resolved] = $mtime;
                }
            }
        }

        if (empty($candidates)) {
            return null;
        }

        arsort($candidates, SORT_NUMERIC);
        $best = array_key_first($candidates);
        return $best ?: null;
    }

    /**
     * Safely read the tail of a log file
     * @param string $path
     * @param int $lines
     * @return string
     */
    public static function tail_file(string $path, int $lines = 500): string
    {
        // Validate path is in our whitelist
        $resolved = self::resolve_log_path($path);
        $allowed_paths = array_column(self::get_whitelisted_logs(), 'path');
        if ($resolved === null || !in_array($resolved, $allowed_paths, true)) {
            return 'Access denied: Invalid log file.';
        }

        // Revalidate immediately before reading in case the path changed after listing.
        $resolved = self::resolve_log_path($resolved);
        if ($resolved === null) {
            return 'Log not readable or does not exist.';
        }

        // Limit lines to prevent abuse
        $lines = min(max($lines, 1), 1000);

        try {
            // Use more efficient tail approach
            $content = self::read_file_tail($resolved, $lines);
            return $content;
        } catch (Exception $e) {
            error_log('WAZM Logs Error: ' . $e->getMessage());
            return 'Error reading log file.';
        }
    }

    /**
     * Efficiently read the tail of a file using reverse reading
     * @param string $path
     * @param int $lines
     * @return string
     */
    private static function read_file_tail(string $path, int $lines): string
    {
        $size = filesize($path);
        if ($size === false || $size === 0) {
            return '';
        }

        // For very small files, just read the whole thing
        if ($size <= 8192) { // 8KB threshold
            $content = file_get_contents($path);
            if ($content === false) {
                return 'Unable to read log file.';
            }

            $rows = preg_split("/\r?\n/", $content);
            $rows = array_slice($rows, -$lines);
            return implode("\n", $rows);
        }

        // For larger files, read from end efficiently
        $fp = fopen($path, 'rb');
        if (!$fp) {
            return 'Unable to open log file.';
        }

        $buffer_size = 4096; // 4KB chunks
        $lines_found = 0;
        $content = '';
        $position = $size;

        // Read backwards from end of file
        while ($position > 0 && $lines_found < $lines) {
            $read_size = min($buffer_size, $position);
            $position -= $read_size;

            fseek($fp, $position);
            $chunk = fread($fp, $read_size);

            if ($chunk === false) {
                break;
            }

            // Prepend chunk to content
            $content = $chunk . $content;

            // Count lines in this chunk
            $lines_found += substr_count($chunk, "\n");
        }

        fclose($fp);

        // Split into lines and get the last N lines
        $rows = preg_split("/\r?\n/", $content);
        $rows = array_slice($rows, -$lines);

        return implode("\n", $rows);
    }

    /**
     * Clear logs cache (call when log files change)
     */
    public static function clear_cache(): void
    {
        wp_cache_delete(self::CACHE_KEY, 'wazm');
    }
}
