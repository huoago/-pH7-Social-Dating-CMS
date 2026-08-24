<section class="dc-account-list-page">
    <header class="dc-discovery-header">
        <div>
            <span class="dc-eyebrow">Tu cuenta</span>
            <h1>Mis favoritos</h1>
            <p>Guarda perfiles para volver a encontrarlos sin convertirlos automáticamente en amigos o contactos.</p>
        </div>
        <div class="dc-discovery-actions">
            <a class="btn btn-default" href="{{ $design->url('user','browse','nearby') }}">📍 Cerca de mí</a>
            <a class="btn btn-primary" href="{{ $design->url('user','browse','index') }}">Explorar</a>
        </div>
    </header>

    {if empty($users)}
        <div class="dc-empty-state">
            <span class="dc-empty-icon" role="img" aria-label="Favoritos">♡</span>
            <h2>Todavía no guardaste perfiles</h2>
            <p>Cuando encuentres un perfil que quieras revisar después, usa el botón Guardar.</p>
            <a class="btn btn-primary" href="{{ $design->url('user','browse','index') }}">Descubrir perfiles</a>
        </div>
    {else}
        <div class="dc-profile-grid">
            {each $user in $users}
                {{ $age = UserBirthDateCore::getAgeFromBirthDate($user->birthDate) }}
                <article class="dc-profile-card">
                    <a class="dc-profile-photo" href="{% (new UserCore)->getProfileLink($user->username) %}">
                        {{ $avatarDesign->get($user->username, $user->firstName, $user->sex, 400) }}
                        {{ UserDesignCoreModel::userStatus($user->profileId) }}
                    </a>
                    <div class="dc-profile-card-body">
                        <div class="dc-profile-title-row">
                            <a href="{% (new UserCore)->getProfileLink($user->username) %}"><strong>{% $user->username %}</strong></a>
                            <span>{% $age %}</span>
                        </div>
                        <div class="dc-profile-location">📍 {% $str->upperFirst($user->city) %}{if !empty($user->state)}, {% $str->upperFirst($user->state) %}{/if}</div>
                        <div class="dc-profile-tags"><span>Guardado</span></div>
                    </div>
                </article>
            {/each}
        </div>
        <div class="dc-pagination">{main_include 'page_nav.inc.tpl'}</div>
    {/if}
</section>
