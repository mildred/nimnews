import templates

proc layout*(main, nav, title, login: string): string = tmpli html"""
  <html>
    <head>
      <link rel=stylesheet href="/style.css" />
      <title>$title - NewsWeb</title>
    </head>
    <body>
      <div class="content">
        <div class="main">$main</div>
        $if nav != "" {
          <nav>$nav</nav>
        }
      </div>
      <div class="login">
        $if login == "" {
          <form action="/login">
            <input type="text" placeholder="email" name="email" />
            <input type="password" placeholder="password" name="pass" />
            <input type="submit" value="Log-In" />
          </form>
          <form action="/register">
            <input type="text" placeholder="email" name="email" />
            <input type="submit" value="Register" />
          </form>
        }
        $if login != "" {
          <form action="/logout">
            <input type="submit" value="Log-Out" />
          </form>
        }
      </div>
    </body>
  </html>
  """

