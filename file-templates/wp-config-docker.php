<?php

/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the
 * installation. You don't have to use the web site, you can
 * copy this file to "wp-config.php" and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * This has been slightly modified (to read environment variables) for use in Docker.
 *
 * @link https://wordpress.org/support/article/editing-wp-config-php/
 *
 * @package WordPress
 */

// IMPORTANT: this file needs to stay in-sync with https://github.com/WordPress/WordPress/blob/master/wp-config-sample.php
// (it gets parsed by the upstream wizard in https://github.com/WordPress/WordPress/blob/f27cb65e1ef25d11b535695a660e7282b98eb742/wp-admin/setup-config.php#L356-L392)

// a helper function to lookup "env_FILE", "env", then fallback
function getenv_docker($env, $default)
{
  if ($fileEnv = getenv($env . '_FILE')) {
    return file_get_contents($fileEnv);
  } else if ($val = getenv($env)) {
    return $val;
  } else {
    return $default;
  }
}

// CDN host name config - add HOST_NAME as a slot setting in app service app settings

$envDomain = getenv('HOST_DOMAIN');
if ($envDomain) {
  $_SERVER['HTTP_HOST'] = $envDomain;
}

$domain = isset($_SERVER['HTTP_HOST']) ? preg_replace('/[^A-Za-z0-9\-\.:]/', '', $_SERVER['HTTP_HOST']) : 'localhost';
if ($envDomain) {
  $domain = $envDomain;
}

// Disable WP's built-in cron when using system cron (default for this image)
$useSystemCron = getenv_docker('USE_SYSTEM_CRON', '1');
define('DISABLE_WP_CRON', ($useSystemCron === '1' || strtolower($useSystemCron) === 'true'));

$value = getenv("MYSQLCONNSTR_defaultConnection");

$connectstr_dbhost = preg_replace("/^.*Data Source=(.+?);.*$/", "\\1", $value);
$connectstr_dbname = preg_replace("/^.*Database=(.+?);.*$/", "\\1", $value);
$connectstr_dbusername = preg_replace("/^.*User Id=(.+?);.*$/", "\\1", $value);
$connectstr_dbpassword = preg_replace("/^.*Password=(.+?)$/", "\\1", $value);

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define('DB_NAME', $connectstr_dbname);

/** MySQL database username */
define('DB_USER', $connectstr_dbusername);

/** MySQL database password */
define('DB_PASSWORD', $connectstr_dbpassword);

// Connection behavior: secure by default; relax for local/dev
$defaultDbPort = getenv('WORDPRESS_DB_PORT') ?: '3306';
$isLocalDev = (
  in_array($connectstr_dbhost, ['db', 'localhost', '127.0.0.1'], true)
);

if ($isLocalDev) {
  if (!defined('MYSQL_CLIENT_FLAGS')) define('MYSQL_CLIENT_FLAGS', 0);
  if (!defined('MYSQL_SSL_CA')) define('MYSQL_SSL_CA', null);
  if (!defined('USE_PCONNECT')) define('USE_PCONNECT', false);
  define('DB_HOST', $connectstr_dbhost . ':' . $defaultDbPort);
} else {
  if (!defined('MYSQL_CLIENT_FLAGS')) define('MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL | MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT);
  if (!defined('MYSQL_SSL_CA')) define('MYSQL_SSL_CA', '/usr/DigiCertGlobalRootG2.crt.pem');
  if (!defined('USE_PCONNECT')) define('USE_PCONNECT', true);
  define('DB_HOST', 'p:' . $connectstr_dbhost . ':' . $defaultDbPort);
}

/** Database Charset to use in creating database tables. */
define('DB_CHARSET', 'utf8');

/** The Database Collate type. Don't change this if in doubt. */
define('DB_COLLATE', '');

/**#@+
 * Authentication Unique Keys and Salts.
 *
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY',         getenv_docker('WORDPRESS_AUTH_KEY',         'put your unique phrase here'));
define('SECURE_AUTH_KEY',  getenv_docker('WORDPRESS_SECURE_AUTH_KEY',  'put your unique phrase here'));
define('LOGGED_IN_KEY',    getenv_docker('WORDPRESS_LOGGED_IN_KEY',    'put your unique phrase here'));
define('NONCE_KEY',        getenv_docker('WORDPRESS_NONCE_KEY',        'put your unique phrase here'));
define('AUTH_SALT',        getenv_docker('WORDPRESS_AUTH_SALT',        'put your unique phrase here'));
define('SECURE_AUTH_SALT', getenv_docker('WORDPRESS_SECURE_AUTH_SALT', 'put your unique phrase here'));
define('LOGGED_IN_SALT',   getenv_docker('WORDPRESS_LOGGED_IN_SALT',   'put your unique phrase here'));
define('NONCE_SALT',       getenv_docker('WORDPRESS_NONCE_SALT',       'put your unique phrase here'));
// (See also https://wordpress.stackexchange.com/a/152905/199287)

/**#@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = getenv_docker('WORDPRESS_TABLE_PREFIX', 'wp_');

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define('WP_DEBUG', !!getenv_docker('WORDPRESS_DEBUG', ''));

// If we're behind a proxy server and using HTTPS, we need to alert WordPress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
  $_SERVER['HTTPS'] = 'on';
  define('WP_HOME', 'https://' . $domain);
  define('WP_SITEURL', 'https://' . $domain);
} else {
  define('WP_HOME', 'http://' . $domain);
  define('WP_SITEURL', 'http://' . $domain);
}
// (we include this by default because reverse proxying is extremely common in container environments)

// Configuration values must remain data, never executable PHP from the environment.
if ((string) getenv('WORDPRESS_CONFIG_EXTRA') !== '' || (string) getenv('WORDPRESS_CONFIG_EXTRA_FILE') !== '') {
  throw new RuntimeException('WORDPRESS_CONFIG_EXTRA is no longer supported. Move constants to WORDPRESS_CONFIG_CONSTANTS JSON, or maintain a reviewed wp-config.php.');
}

$configConstants = (string) getenv('WORDPRESS_CONFIG_CONSTANTS');
if ($configConstants === '') {
  $configConstants = null;
}
$configConstantsFile = (string) getenv('WORDPRESS_CONFIG_CONSTANTS_FILE');
if ($configConstantsFile !== '') {
  if ($configConstantsFile[0] !== '/' || !is_file($configConstantsFile) || !is_readable($configConstantsFile)) {
    throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS_FILE must point to a readable local file.');
  }
  $configConstants = file_get_contents($configConstantsFile);
  if ($configConstants === false) {
    throw new RuntimeException('Could not read WORDPRESS_CONFIG_CONSTANTS_FILE.');
  }
}

if ($configConstants !== null) {
  try {
    $extraConstants = json_decode($configConstants, false, 512, JSON_THROW_ON_ERROR);
  } catch (JsonException $e) {
    throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS must be a valid JSON object.', 0, $e);
  }

  if (!($extraConstants instanceof stdClass)) {
    throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS must be a JSON object.');
  }

  $booleanConstants = [
    'DISALLOW_FILE_EDIT',
    'DISALLOW_FILE_MODS',
    'AUTOMATIC_UPDATER_DISABLED',
    'WP_DEBUG_DISPLAY',
    'FORCE_SSL_ADMIN',
  ];
  $memoryConstants = ['WP_MEMORY_LIMIT', 'WP_MAX_MEMORY_LIMIT'];
  $allowedConstants = array_merge($booleanConstants, $memoryConstants, ['WP_ENVIRONMENT_TYPE']);
  $environmentTypes = ['production', 'staging', 'development', 'local'];

  // Validate the whole object before applying any constants.
  foreach ($extraConstants as $name => $value) {
    if (!in_array($name, $allowedConstants, true) || defined($name)) {
      throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS contains an unsupported or already defined constant.');
    }

    if (in_array($name, $booleanConstants, true)) {
      if (!is_bool($value)) {
        throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS boolean settings require JSON true or false.');
      }
      continue;
    }

    if (in_array($name, $memoryConstants, true)) {
      if (!is_string($value) || !preg_match('/^([1-9][0-9]{0,6})(K|M|G)$/D', $value, $matches)) {
        throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS memory limits must use a positive K, M, or G size.');
      }

      $size = (int) $matches[1];
      $multiplier = ['K' => 1024, 'M' => 1024 * 1024, 'G' => 1024 * 1024 * 1024][$matches[2]];
      $bytes = $size * $multiplier;
      if ($bytes < 16 * 1024 * 1024 || $bytes > 2 * 1024 * 1024 * 1024) {
        throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS memory limits must be between 16M and 2G.');
      }
      continue;
    }

    if ($name === 'WP_ENVIRONMENT_TYPE' && (!is_string($value) || !in_array($value, $environmentTypes, true))) {
      throw new RuntimeException('WORDPRESS_CONFIG_CONSTANTS WP_ENVIRONMENT_TYPE must be production, staging, development, or local.');
    }
  }
  foreach ($extraConstants as $name => $value) {
    define($name, $value);
  }
}


//Relative URLs for swapping across app service deployment slots
define('WP_CONTENT_URL', '/wp-content');
define('DOMAIN_CURRENT_SITE', $domain);

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if (! defined('ABSPATH')) {
  define('ABSPATH', __DIR__ . '/');
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
