import templates

proc layout*(main, nav, title: string): string = tmpli html"""
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
    </body>
  </html>
  """
