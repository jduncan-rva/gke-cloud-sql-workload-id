FROM python:3.9.5-alpine
RUN apk add --no-cache postgresql-dev gcc libc-dev netcat-openbsd
WORKDIR /app
COPY templates app.py requirements.txt . /app/
RUN pip install -r requirements.txt
CMD ["python","app.py"]