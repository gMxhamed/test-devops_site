<?php
require_once 'db.php';

if ($_SERVER["REQUEST_METHOD"] === "POST") {
  $nom = htmlspecialchars($_POST["nom"]);
  $email = htmlspecialchars($_POST["email"]);
  $message = htmlspecialchars($_POST["message"]);

  $sql = "INSERT INTO messages (nom, email, message) VALUES (?, ?, ?)";
  $stmt = $pdo->prepare($sql);
  $stmt->execute([$nom, $email, $message]);

  echo "<p>Thank you <strong>$nom</strong> for your message!</p>";
  echo "<a href='index.php'>Back to home</a>";
} else {
  header("Location: contact.php");
  exit();
}
?>
