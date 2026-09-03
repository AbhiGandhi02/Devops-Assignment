from flask import Flask

flask_app = Flask(__name__)


@flask_app.route("/")
def greet():
    return "<h1>Hello World from Abhi's Python (Flask) app!</h1>"


if __name__ == "__main__":
    flask_app.run(host="0.0.0.0", port=5000)
