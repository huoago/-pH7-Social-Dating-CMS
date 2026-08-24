<section class="dc-account-list-page">
    <header class="dc-discovery-header">
        <div>
            <span class="dc-eyebrow">Seguridad</span>
            <h1>Perfiles bloqueados</h1>
            <p>Los perfiles bloqueados dejan de aparecer en tu descubrimiento y no deben poder iniciar nuevas interacciones contigo.</p>
        </div>
        <div class="dc-discovery-actions">
            <a class="btn btn-primary" href="{{ $design->url('user','browse','index') }}">Volver a explorar</a>
        </div>
    </header>

    {if empty($users)}
        <div class="dc-empty-state">
            <span class="dc-empty-icon" role="img" aria-label="Bloqueados">🛡</span>
            <h2>No tienes perfiles bloqueados</h2>
            <p>Desde cualquier perfil puedes bloquear a una persona y gestionar después la lista desde aquí.</p>
        </div>
    {else}
        <div class="dc-profile-grid">
            {each $user in $users}
                <article class="dc-profile-card">
                    <div class="dc-profile-photo">
                        {{ $avatarDesign->get($user->username, $user->firstName, $user->sex, 400) }}
                    </div>
                    <div class="dc-profile-card-body">
                        <div class="dc-profile-title-row"><strong>{% $user->username %}</strong></div>
                        <div class="dc-profile-location">📍 {% $str->upperFirst($user->city) %}{if !empty($user->state)}, {% $str->upperFirst($user->state) %}{/if}</div>
                        <form method="post" action="{{ $design->url('user','block','toggle') }}" class="dc-inline-form">
                            <input type="hidden" name="security_token" value="{block_csrf}" />
                            <input type="hidden" name="blocked_id" value="{% $user->profileId %}" />
                            <button type="submit" class="btn btn-default btn-sm">Desbloquear</button>
                        </form>
                    </div>
                </article>
            {/each}
        </div>
        <div class="dc-pagination">{main_include 'page_nav.inc.tpl'}</div>
    {/if}
</section>
