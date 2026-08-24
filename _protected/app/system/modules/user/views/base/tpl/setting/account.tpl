<div class="col-md-10 deseocerca-account-management">
    <h3>Desactivar cuenta temporalmente</h3>
    <p>
        La desactivación oculta tu perfil y bloquea el acceso normal, pero conserva tus datos.
        Podrás reactivar la cuenta usando el enlace seguro que enviaremos a tu correo.
    </p>
    {{ DeactivateAccountForm::display() }}

    <hr />

    <h3>Eliminar cuenta</h3>
    <p>
        Si solicitas la eliminación, la cuenta se desactiva inmediatamente y entra en un período de recuperación de 90 días.
        Si no la recuperas dentro de ese plazo, la eliminación definitiva se ejecutará mediante el proceso de mantenimiento.
    </p>
    <p>
        <a class="btn btn-danger" href="{{ $design->url('user','setting','delete') }}">
            Solicitar eliminación de la cuenta
        </a>
    </p>
</div>
