<?php
///////////////////////////////////////////////////////////////////////////
//                                                                       //
// Moodle configuration file                                             //
//                                                                       //
// This file should be renamed "config.php" in the top-level directory   //
//                                                                       //
///////////////////////////////////////////////////////////////////////////
//                                                                       //
// NOTICE OF COPYRIGHT                                                   //
//                                                                       //
// Moodle - Modular Object-Oriented Dynamic Learning Environment         //
//          http://moodle.org                                            //
//                                                                       //
// Copyright (C) 1999 onwards  Martin Dougiamas  http://moodle.com       //
//                                                                       //
// This program is free software; you can redistribute it and/or modify  //
// it under the terms of the GNU General Public License as published by  //
// the Free Software Foundation; either version 3 of the License, or     //
// (at your option) any later version.                                   //
//                                                                       //
// This program is distributed in the hope that it will be useful,       //
// but WITHOUT ANY WARRANTY; without even the implied warranty of        //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         //
// GNU General Public License for more details:                          //
//                                                                       //
//          http://www.gnu.org/copyleft/gpl.html                         //
//                                                                       //
///////////////////////////////////////////////////////////////////////////
unset($CFG);  // Ignore this line
global $CFG;  // This is necessary here for PHPUnit execution
$CFG = new stdClass();

$CFG->dbtype    = 'mariadb';   
$CFG->dblibrary = 'native';     
$CFG->dbhost    = 'db';  
$CFG->dbname    = 'moodle';     
$CFG->dbuser    = 'moodleuser';
$CFG->dbpass    = 'moodlepass';
$CFG->dbport    = '3306';
$CFG->prefix    = 'mdl_'; 
$CFG->dboptions = [
  'dbpersist' => 0,
  'dbsocket' => '',
  'dbcollation' => 'utf8mb4_unicode_ci',
];
$public_port = trim(file_get_contents("/PUBLIC_PORT"));
$CFG->wwwroot = "http://localhost:{$public_port}";
$CFG->wwwrootendsinpublic = false;
$CFG->dataroot  = '/var/www/moodledata';
$CFG->routerconfigured = false;
$CFG->directorypermissions = 02777;
$CFG->admin = 'admin';
// $CFG->reverseproxy = true;
// $CFG->sslproxy = false;

require_once(__DIR__ . '/lib/setup.php'); // Do not edit

// There is no php closing tag in this file,
// it is intentional because it prevents trailing whitespace problems!