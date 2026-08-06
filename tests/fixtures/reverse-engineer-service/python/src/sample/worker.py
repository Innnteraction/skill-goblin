from celery import Celery

app = Celery("sample")


@app.task
def process_order(order_id):
    return order_id
