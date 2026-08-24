<div class="center">
    {if !$delete_status}
        <p class="bold green1">
            La solicitud de eliminación fue cancelada. Tu cuenta permanece activa.
        </p>
    {else}
        <p class="bold red">
            ¿Confirmas que quieres iniciar la eliminación de tu cuenta?
        </p>
        <p>
            Tu cuenta se desactivará inmediatamente. Tendrás 90 días para recuperarla mediante el enlace enviado a tu correo.
            Transcurrido ese plazo, la eliminación definitiva será ejecutada por el proceso de mantenimiento.
        </p>

        <ul>
            <li>
                <a class="bold" href="{{ $design->url('user','setting','delete','nodelete') }}">
                    No, mantener mi cuenta activa
                </a>
            </li>
            <li>
                <a href="{{ $design->url('user','setting','delete','yesdelete') }}">
                    Sí, continuar con la solicitud de eliminación
                </a>
            </li>
        </ul>
    {/if}
</div>
