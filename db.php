<?php
try {
  $pdo = new PDO('mysql:host=localhost;dbname=devops_site;charset=utf8', 'devops', '$uperPa$$_2025');
  $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (Exception $e) {
  die('Connection error: ' . $e->getMessage());
}
?>
