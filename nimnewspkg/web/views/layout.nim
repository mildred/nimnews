import templates

proc layout*(main, nav, title, login, from_name: string): string = tmpli html"""
  <html>
    <head>
      <link rel=stylesheet href="/style.css" />
      <title>$title - NewsWeb</title>
    </head>
    <body>
      <div class="content">
        <div class="main">$main</div>
        <nav>
          <div class="login">
            $if login == "" {
              <a href="#login-form">Log-In</a>
              <a href="#register-form">Register</a>
              <form id="login-form" action="/login">
                <input type="text" placeholder="email" name="email" />
                <input type="password" placeholder="password" name="pass" />
                $if from_name == "" {
                  <input name="from_name" type="text" placeholder="Your name (optional)" value="$from_name" />
                }
                <input type="submit" value="Log-In" />
                <a href="#">Cancel</a>
              </form>
              <form id="register-form" action="/register">
                <input type="text" placeholder="email" name="email" />
                <input type="submit" value="Register" />
                <a href="#">Cancel</a>
              </form>
            }
            $if login != "" {
              <a href="/logout">Log-Out</a>
            }
          </div>
          $if nav != "" {
            <div>$nav</div>
          }
        </nav>
      </div>
    </body>
  </html>
  """

