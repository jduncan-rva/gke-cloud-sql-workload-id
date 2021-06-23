#!/usr/bin/python
import psycopg2
from flask import Flask, render_template


app = Flask(__name__)

@app.route('/')
def index():

  conn = psycopg2.connect(dbname="sample-app", user="sample-psql-gsa@$PROJECT", sslmode="disable", host="localhost")
  cur = conn.cursor()
  cur.execute("""select name, membercost from facilities""")

  rows = cur.fetchall()

  return render_template('index.html', rows=rows)


if __name__ == '__main__':
  app.run(debug=True,host='0.0.0.0',port=8080)
