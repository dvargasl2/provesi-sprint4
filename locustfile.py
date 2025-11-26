from locust import HttpUser, task, between

class OrderDetailTest(HttpUser):
    wait_time = between(1, 3)

    @task
    def get_order_full(self):
        self.client.get("/orders/1/full")
