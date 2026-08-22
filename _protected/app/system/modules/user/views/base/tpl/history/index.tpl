<section class="dc-account-list-page">
    <header class="dc-discovery-header">
        <div>
            <span class="dc-eyebrow">Tu actividad</span>
            <h1>Vistos recientemente</h1>
            <p>Recupera rápidamente los perfiles que abriste desde tu cuenta.</p>
        </div>
        <div class="dc-discovery-actions">
            <a class="btn btn-default" href="{{ $design->url('user','favorite','index') }}">♡ Favoritos</a>
            <a class="btn btn-primary" href="{{ $design->url('user','browse','nearby') }}">📍 Cerca de mí</a>
        </div>
    </header>

    {if empty($users)}
        <div class="dc-empty-state">
            <span class="dc-empty-icon" role="img" aria-label="Historial">◷</span>
            <h2>Aún no hay perfiles recientes</h2>
            <p>Los perfiles que visites aparecerán aquí mientras el registro de visitas esté habilitado en tu privacidad.</p>
            <a class="btn btn-primary" href="{{ $design->url('user','browse','index') }}">Explorar perfiles</a>
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
                        <div class="dc-profile-tags"><span>Visto recientemente</span></div>
                    </div>
                </article>
            {/each}
        </div>
        <div class="dc-pagination">{main_include 'page_nav.inc.tpl'}</div>
    {/if}
</section>
