from django.http import JsonResponse, Http404
from django.views.decorators.http import require_GET
from api.models import Order


@require_GET
def order_detail(request, order_id: int):
    try:
        order = Order.objects.get(pk=order_id)
    except Order.DoesNotExist:
        raise Http404("Pedido no encontrado")

    data = {
        "id": order.id,
        "customer_name": order.customer_name,
        "status": order.status,
        "warehouse": order.warehouse,
        "total_amount": float(order.total_amount),
        "created_at": order.created_at.isoformat(),
        "updated_at": order.updated_at.isoformat(),

        "ownerVendorId": order.warehouse,
    }
    return JsonResponse(data)