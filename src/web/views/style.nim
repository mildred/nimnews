proc style*(): string = """

  body {
    margin: 0;
    padding: 0;
    height: 100%;
    display: flex;
    flex-flow: column nowrap;
  }

  body > .content {
    height: 0;
    flex: 1 0 auto;
    display: flex;
    flex-flow: row nowrap;
  }

  body > .content > * {
    overflow: auto;
  }

  body > .content > nav {
    order: -1;
    flex: 0 1 auto;
  }

  body > .content > .main {
    flex: 1 0 auto;
  }

  #login-form:not(:target), #register-form:not(:target), form#post:not(:target) {
    display: none;
  }

  #login-form > *, #register-form > *, form#post > *, form.reply-post > * {
    display: block;
    width: 100%;
  }

  """
