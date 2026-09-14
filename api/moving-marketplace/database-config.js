'use strict';

const fs = require('fs');
const path = require('path');

function readPhpConstant(source, name) {
  const expression = new RegExp(
    `define\\(\\s*['"]${name}['"]\\s*,\\s*(['"])(.*?)\\1\\s*\\)`,
    's',
  );
  const match = source.match(expression);
  if (!match) return '';

  return match[2]
    .replace(/\\\\'/g, "'")
    .replace(/\\\\"/g, '"')
    .replace(/\\\\\\\\/g, '\\');
}

function loadPhpDatabaseConfig() {
  const configPath = path.resolve(__dirname, '../../config/config.php');
  if (!fs.existsSync(configPath)) return {};

  const source = fs.readFileSync(configPath, 'utf8');
  return {
    host: readPhpConstant(source, 'DB_HOST'),
    user: readPhpConstant(source, 'DB_USER'),
    password: readPhpConstant(source, 'DB_PASS'),
    database: readPhpConstant(source, 'DB_NAME'),
  };
}

function loadDatabaseConfig() {
  const php = loadPhpDatabaseConfig();
  const config = {
    host: process.env.DB_HOST || php.host || 'localhost',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER || php.user,
    password: process.env.DB_PASSWORD || process.env.DB_PASS || php.password,
    database: process.env.DB_NAME || php.database,
  };

  if (!config.user || !config.database) {
    throw new Error(
      'Database configuration is missing. Set DB_USER and DB_NAME in cPanel or config/config.php.',
    );
  }

  return config;
}

module.exports = { loadDatabaseConfig };
