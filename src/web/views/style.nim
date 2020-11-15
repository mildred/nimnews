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
    max-width: 40rem;
  }

  textarea {
    height: 10em;
  }

  /***** Style articles *****/

  .article-list, .article-thread, .post-form {
    --border-color: rgba(1, 1, 1, 0.1);
    --article-color: rgba(1, 1, 1, 0.05);
  }

  hr.article-separation {
    display: none;
  }

  .article-list > ul, .article-thread > ul {
    margin: 0;
    padding: 0;
  }

  li.thread, div.post-form {
    border: thin solid var(--border-color);
    list-style-type: none;
    margin: 0.5rem;
    padding: 0.5rem;
    background-color: var(--article-color);
  }

  li.thread {
    padding: 0
  }

  .article-thread li.thread > article {
    margin: 0;
    padding: 0.5rem;
  }

  .article-thread li.thread > article:not(:first-child) {
    border-top: thin solid var(--border-color);
  }

  .article-list li.thread > p {
    margin: 0;
    padding: 0.5rem;
  }

  .article-list li.thread > p:not(:first-child) {
    border-top: thin solid var(--border-color);
  }
  """
