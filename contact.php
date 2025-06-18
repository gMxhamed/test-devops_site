<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>DevOps - Contact</title>
  <link rel="stylesheet" href="style.css">
  <script src="script.js" defer></script>
</head>
<body>
  <header>
    <h1>Contact DevOps</h1>
    <nav>
      <a href="index.php">Home</a>
      <a href="contact.php">Contact</a>
    </nav>
  </header>

  <main>
    <section>
      <h2>Contact Form</h2>
      <form action="envoyer.php" method="post" onsubmit="return validateForm()">
        <label for="name">Name:</label>
        <input type="text" id="name" name="nom" required>

        <label for="email">Email:</label>
        <input type="email" id="email" name="email" required>

        <label for="message">Message:</label>
        <textarea id="message" name="message" required></textarea>

        <button type="submit">Send</button>
      </form>
    </section>
  </main>

  <footer>
    <p>&copy; 2025 DevOps. All rights reserved.</p>
  </footer>
</body>
</html>


hello
