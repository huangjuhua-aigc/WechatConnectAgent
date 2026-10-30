#!/usr/bin/env node
'use strict';
require('../lib/install.cjs').main(process.argv.slice(2)).catch(error => {
  console.error(`Installation stopped: ${error.message}`);
  process.exitCode = 1;
});
